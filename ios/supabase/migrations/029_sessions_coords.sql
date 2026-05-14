-- Optional latitude/longitude on sessions so the home weather card can
-- fetch a forecast tailored to the actual court. Nullable: when unset,
-- the weather card simply hides. Admins can set these per-session via
-- SQL or a future admin UI.

ALTER TABLE public.sessions
    ADD COLUMN IF NOT EXISTS latitude double precision,
    ADD COLUMN IF NOT EXISTS longitude double precision;
