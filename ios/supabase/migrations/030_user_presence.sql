-- user_presence: explicit heartbeat-based presence. Each signed-in iOS
-- client upserts their row every ~25s while the app is foregrounded.
-- "Online" = last_seen_at within the last 60s. More deterministic than
-- Phoenix Presence (which has been flaky in this project) — you can
-- literally SELECT to verify, and survives realtime tenant restarts.

CREATE TABLE IF NOT EXISTS public.user_presence (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    last_seen_at timestamptz NOT NULL DEFAULT NOW(),
    display_name text
);

CREATE INDEX IF NOT EXISTS user_presence_last_seen_idx ON public.user_presence (last_seen_at DESC);

ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can read presence"
    ON public.user_presence FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "User can insert own presence"
    ON public.user_presence FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "User can update own presence"
    ON public.user_presence FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

ALTER PUBLICATION supabase_realtime ADD TABLE public.user_presence;

-- Bumps the caller's last_seen_at. Convenient SECURITY DEFINER so a
-- single RPC handles upsert + display_name pickup from profiles.
CREATE OR REPLACE FUNCTION public.touch_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  caller uuid := auth.uid();
  name text;
BEGIN
  IF caller IS NULL THEN
    RETURN;
  END IF;
  SELECT display_name INTO name FROM profiles WHERE id = caller;
  INSERT INTO user_presence (user_id, last_seen_at, display_name)
  VALUES (caller, NOW(), name)
  ON CONFLICT (user_id) DO UPDATE
    SET last_seen_at = NOW(),
        display_name = EXCLUDED.display_name;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.touch_presence() TO authenticated;
