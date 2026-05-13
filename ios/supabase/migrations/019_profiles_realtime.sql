-- Publish profile changes so a muted user's chat UI flips to the muted
-- banner the instant an admin toggles is_muted, instead of requiring a
-- relaunch or tab bounce.

ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
