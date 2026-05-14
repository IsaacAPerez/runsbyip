-- Fix send_one_hour_reminders() to respect Pacific time.
--
-- Bug: the original function cast (date || ' ' || time)::timestamp, producing
-- a naive timestamp that postgres interprets as UTC. With the DB session
-- timezone set to UTC, a 10pm-PT session was being treated as 10pm-UTC, so
-- the reminder fired ~7 hours early (when 22:00 UTC fell in the 45-75min
-- lookahead, around 1:45pm PT). The s.date = CURRENT_DATE filter also
-- evaluates in UTC, which silently drops late-evening PT games that have
-- already rolled over into the next UTC day.
--
-- Fix: build the session instant as ((date || ' ' || time)::timestamp AT
-- TIME ZONE 'America/Los_Angeles'), producing a real timestamptz that
-- compares correctly against NOW(). Drop the day filter — the 45-75min
-- window is already a tight enough bound and a full scan of the small
-- sessions table is cheap.

CREATE OR REPLACE FUNCTION public.send_one_hour_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  sess RECORD;
BEGIN
  FOR sess IN
    SELECT s.id, s.date, s.time, s.location
    FROM sessions s
    WHERE s.status IN ('open', 'confirmed')
      AND ((s.date || ' ' || s.time)::timestamp AT TIME ZONE 'America/Los_Angeles')
          BETWEEN NOW() + interval '45 minutes'
          AND NOW() + interval '75 minutes'
      AND NOT EXISTS (
        SELECT 1 FROM push_log pl
        WHERE pl.session_id = s.id
          AND pl.notification_type = 'one_hour_reminder'
      )
  LOOP
    PERFORM net.http_post(
      url := 'https://ncjgkthruvapcogqaxhi.supabase.co/functions/v1/send-push',
      body := json_build_object(
        'type', 'one_hour_reminder',
        'session_id', sess.id,
        'title', 'Tip-off in 1 hour!',
        'body', 'See you at ' || sess.location || '. Don''t be late.'
      )::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  END LOOP;
END;
$function$;
