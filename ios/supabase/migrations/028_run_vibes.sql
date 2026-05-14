-- Run vibes: post-game thumbs-style rating ("fire" / "mid" / "dud").
-- Surfaces on the home page when the most recent past session has
-- status = 'completed' and the user hasn't voted yet.

CREATE TABLE IF NOT EXISTS public.run_vibes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vibe text NOT NULL CHECK (vibe IN ('fire', 'mid', 'dud')),
    created_at timestamptz NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS run_vibes_session_idx ON public.run_vibes (session_id);

ALTER TABLE public.run_vibes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can read vibes"
    ON public.run_vibes FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Users can insert own vibe"
    ON public.run_vibes FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own vibe"
    ON public.run_vibes FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own vibe"
    ON public.run_vibes FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

ALTER PUBLICATION supabase_realtime ADD TABLE public.run_vibes;

-- Aggregate tally for a single session.
CREATE OR REPLACE FUNCTION public.run_vibe_tally(p_session_id uuid)
RETURNS TABLE(vibe text, votes int)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT vibe, count(*)::int AS votes
  FROM run_vibes
  WHERE session_id = p_session_id
  GROUP BY vibe;
$function$;

GRANT EXECUTE ON FUNCTION public.run_vibe_tally(uuid) TO authenticated;
