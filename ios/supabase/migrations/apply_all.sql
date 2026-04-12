-- Combined idempotent migration: run this in the Supabase SQL editor.
-- Safe to run multiple times — uses IF NOT EXISTS / IF EXISTS everywhere.

-- ============================================================
-- 1. PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view all profiles' AND tablename = 'profiles') THEN
    CREATE POLICY "Users can view all profiles" ON profiles FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own profile' AND tablename = 'profiles') THEN
    CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own profile' AND tablename = 'profiles') THEN
    CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(COALESCE(NEW.email,''), '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Backfill profiles for existing auth users who don't have one yet
INSERT INTO profiles (id, email, display_name)
SELECT
  id,
  COALESCE(email, ''),
  COALESCE(raw_user_meta_data->>'display_name', split_part(COALESCE(email,''), '@', 1))
FROM auth.users
WHERE id NOT IN (SELECT id FROM profiles)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 2. DEVICE TOKENS
-- ============================================================
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL DEFAULT 'ios',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own tokens' AND tablename = 'device_tokens') THEN
    CREATE POLICY "Users manage own tokens" ON device_tokens FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

-- ============================================================
-- 3. MESSAGES
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  display_name TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '' CHECK (char_length(content) <= 500),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text';
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attachment_path TEXT;

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone authenticated can read messages' AND tablename = 'messages') THEN
    CREATE POLICY "Anyone authenticated can read messages" ON messages FOR SELECT USING (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can insert messages' AND tablename = 'messages') THEN
    CREATE POLICY "Authenticated users can insert messages" ON messages FOR INSERT WITH CHECK (auth.uid() = user_id AND auth.role() = 'authenticated');
  END IF;
END $$;

-- ============================================================
-- 4. MESSAGE REACTIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  emoji TEXT NOT NULL CHECK (char_length(emoji) <= 8),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (message_id, user_id, emoji)
);

ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can read reactions' AND tablename = 'message_reactions') THEN
    CREATE POLICY "Authenticated users can read reactions" ON message_reactions FOR SELECT USING (auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can insert own reactions' AND tablename = 'message_reactions') THEN
    CREATE POLICY "Authenticated users can insert own reactions" ON message_reactions FOR INSERT WITH CHECK (auth.uid() = user_id AND auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated users can delete own reactions' AND tablename = 'message_reactions') THEN
    CREATE POLICY "Authenticated users can delete own reactions" ON message_reactions FOR DELETE USING (auth.uid() = user_id AND auth.role() = 'authenticated');
  END IF;
END $$;

-- ============================================================
-- 5. RSVPS — add checked_in if missing
-- ============================================================
ALTER TABLE rsvps ADD COLUMN IF NOT EXISTS checked_in BOOLEAN DEFAULT FALSE;

-- ============================================================
-- 6. REALTIME — safe to re-add (errors are harmless)
-- ============================================================
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE messages;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE message_reactions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 7. SINGLE SOURCE OF TRUTH — avatar via view, drop denormalized cols
-- ============================================================

-- Drop stale avatar_url from messages (now comes from profiles via view)
ALTER TABLE messages DROP COLUMN IF EXISTS avatar_url;

-- Drop display_name from reactions (not needed — aggregated by emoji)
ALTER TABLE message_reactions DROP COLUMN IF EXISTS display_name;

-- View: messages joined with live profile data
CREATE OR REPLACE VIEW messages_with_profiles AS
SELECT
  m.id,
  m.user_id,
  COALESCE(p.display_name, m.display_name, '') AS display_name,
  p.avatar_url,
  m.content,
  m.message_type,
  m.attachment_path,
  m.created_at
FROM messages m
LEFT JOIN profiles p ON p.id = m.user_id;

-- PostgREST: expose view to API roles
GRANT SELECT ON messages_with_profiles TO authenticated;
GRANT SELECT ON messages_with_profiles TO service_role;
