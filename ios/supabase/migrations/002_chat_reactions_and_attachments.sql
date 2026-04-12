-- Chat upgrades: photo attachments + emoji reactions

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text'
    CHECK (message_type IN ('text', 'photo')),
  ADD COLUMN IF NOT EXISTS attachment_path TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_photo_requires_attachment'
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT messages_photo_requires_attachment
      CHECK (
        (message_type = 'text' AND attachment_path IS NULL)
        OR (message_type = 'photo' AND attachment_path IS NOT NULL)
      );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  display_name TEXT NOT NULL,
  emoji TEXT NOT NULL CHECK (char_length(emoji) <= 8),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (message_id, user_id, emoji)
);

ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read reactions"
  ON message_reactions FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert own reactions"
  ON message_reactions FOR INSERT
  WITH CHECK (auth.uid() = user_id AND auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete own reactions"
  ON message_reactions FOR DELETE
  USING (auth.uid() = user_id AND auth.role() = 'authenticated');

ALTER PUBLICATION supabase_realtime ADD TABLE message_reactions;

-- External setup still required in Supabase dashboard:
-- 1) create storage bucket `chat-media`
-- 2) make it public or adjust the iOS client to use signed URLs instead of getPublicURL
-- 3) add storage RLS so authenticated users can upload into their own folder path
