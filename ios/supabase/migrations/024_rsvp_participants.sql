-- RPC that returns the RSVPs for a session joined to profiles (by email)
-- so the iOS home card can show "who's coming" as a stack of avatars.
-- SECURITY DEFINER because the join needs to surface profile data based
-- on the rsvp's player_email even when the caller doesn't directly have
-- visibility into other profiles. Volatile-set search_path keeps this
-- safe; only public + pg_catalog.

CREATE OR REPLACE FUNCTION public.rsvp_participants_for_session(p_session_id uuid)
RETURNS TABLE(user_id uuid, name text, email text, avatar_url text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
  SELECT
    p.id AS user_id,
    COALESCE(p.display_name, r.player_name) AS name,
    r.player_email AS email,
    p.avatar_url,
    r.created_at
  FROM rsvps r
  LEFT JOIN profiles p ON lower(p.email) = lower(r.player_email)
  WHERE r.session_id = p_session_id
  ORDER BY r.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.rsvp_participants_for_session(uuid) TO authenticated, anon;
