-- attendance_streak_for_email: count consecutive most-recent past
-- sessions (status not cancelled) where this email has an RSVP, going
-- backwards from the latest past session until the first gap. Used by
-- the home page to show "🔥 N week streak" personal motivation.

CREATE OR REPLACE FUNCTION public.attendance_streak_for_email(p_email text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  sess RECORD;
  streak integer := 0;
  email_lc text := lower(p_email);
BEGIN
  IF email_lc IS NULL OR email_lc = '' THEN
    RETURN 0;
  END IF;

  -- Walk past sessions newest-to-oldest. Stop on the first session the
  -- email did NOT RSVP to. We exclude future sessions and cancelled
  -- ones (those don't count for or against a streak).
  FOR sess IN
    SELECT s.id
    FROM sessions s
    WHERE s.status <> 'cancelled'
      AND (s.date || ' ' || s.time)::timestamp
            AT TIME ZONE 'America/Los_Angeles' < NOW()
    ORDER BY (s.date || ' ' || s.time)::timestamp
            AT TIME ZONE 'America/Los_Angeles' DESC
  LOOP
    IF EXISTS (
      SELECT 1 FROM rsvps r
      WHERE r.session_id = sess.id
        AND lower(r.player_email) = email_lc
    ) THEN
      streak := streak + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  RETURN streak;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.attendance_streak_for_email(text) TO authenticated;
