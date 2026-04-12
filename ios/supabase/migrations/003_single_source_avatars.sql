-- Single source of truth for avatars and display names.
-- Profiles table is the authority — stop denormalizing into messages.

-- 1. Add avatar_url + bio to profiles if missing (may have been added via dashboard)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- 2. Create a view that joins messages with the sender's current profile.
--    The app reads from this view so avatars/display names are always fresh.
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

-- 3. Drop the denormalized avatar_url column from messages.
--    display_name stays for now as a fallback/historical record,
--    but the view overrides it with the live profile value.
ALTER TABLE messages DROP COLUMN IF EXISTS avatar_url;

-- 4. Drop display_name from message_reactions — use profile join instead.
--    The iOS client aggregates reactions in memory by emoji, not by name.
ALTER TABLE message_reactions DROP COLUMN IF EXISTS display_name;
