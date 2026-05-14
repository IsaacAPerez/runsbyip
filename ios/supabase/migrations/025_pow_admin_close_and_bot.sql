-- POW: refactor close logic into a single function so the cron, the
-- admin "close early" button, and the bot announcement message all share
-- one code path. The bot also drops a chat message announcing the winner.

CREATE OR REPLACE FUNCTION public.close_pow_poll(p_poll_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  winner RECORD;
  session_id_var uuid;
  current_status text;
  bot_user_id constant uuid := 'b5589b90-d697-4ef1-af9f-1201047008be';
  bot_display_name constant text := 'botbyisaacperez';
BEGIN
  -- No-op if the poll is already closed; otherwise idempotency would
  -- spam bot messages on repeated calls.
  SELECT status, session_id INTO current_status, session_id_var
  FROM pow_polls WHERE id = p_poll_id;
  IF current_status IS NULL OR current_status <> 'open' THEN
    RETURN;
  END IF;

  SELECT v.voted_for_name, count(*) AS vote_count
  INTO winner
  FROM pow_votes v
  WHERE v.poll_id = p_poll_id
  GROUP BY v.voted_for_name
  ORDER BY count(*) DESC
  LIMIT 1;

  UPDATE pow_polls
  SET status = 'closed',
      winner_name = COALESCE(winner.voted_for_name, 'No votes'),
      winner_votes = COALESCE(winner.vote_count::int, 0),
      closes_at = LEAST(closes_at, NOW())
  WHERE id = p_poll_id;

  -- Only announce if there were votes.
  IF winner.voted_for_name IS NOT NULL THEN
    INSERT INTO messages (id, user_id, display_name, content, message_type)
    VALUES (
      gen_random_uuid(),
      bot_user_id,
      bot_display_name,
      '🏆 Player of the Week: ' || winner.voted_for_name ||
        ' (' || winner.vote_count || ' vote' || CASE WHEN winner.vote_count = 1 THEN '' ELSE 's' END || '). Congrats! 🎉',
      'text'
    );

    PERFORM net.http_post(
      url := 'https://ncjgkthruvapcogqaxhi.supabase.co/functions/v1/send-push',
      body := json_build_object(
        'type', 'pow_winner',
        'session_id', session_id_var::text,
        'title', 'Player of the Week',
        'body', winner.voted_for_name || ' won with ' || winner.vote_count ||
                CASE WHEN winner.vote_count = 1 THEN ' vote!' ELSE ' votes!' END
      )::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  END IF;
END;
$function$;

-- Update the cron-driven closer to delegate to the helper.
CREATE OR REPLACE FUNCTION public.auto_close_pow_polls()
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  poll_id_var uuid;
BEGIN
  FOR poll_id_var IN
    SELECT p.id
    FROM pow_polls p
    WHERE p.status = 'open'
      AND p.closes_at <= NOW()
  LOOP
    PERFORM close_pow_poll(poll_id_var);
  END LOOP;
END;
$function$;

-- Admin-only: close the active poll immediately.
CREATE OR REPLACE FUNCTION public.admin_close_pow_poll(p_poll_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Only admins can close polls early';
  END IF;
  PERFORM close_pow_poll(p_poll_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_close_pow_poll(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_pow_poll(uuid) TO authenticated;
