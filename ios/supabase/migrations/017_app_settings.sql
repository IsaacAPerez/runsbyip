-- Key/value settings table for ad-hoc app config the client + server can read
-- and admins can edit without a deploy. First entry: ios_discount_cents, the
-- discount applied to in-app RSVP purchases to offset web/iOS price parity.
-- The web flow ignores this and charges full price_cents.

CREATE TABLE IF NOT EXISTS public.app_settings (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read settings (used by iOS to derive the
-- displayed price). Service role bypasses RLS, so the edge function is
-- unaffected.
DROP POLICY IF EXISTS app_settings_select ON public.app_settings;
CREATE POLICY app_settings_select
    ON public.app_settings
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

-- Only admins can write. Same gate pattern as elsewhere in the schema:
-- look up the caller's profile row and check role.
DROP POLICY IF EXISTS app_settings_admin_write ON public.app_settings;
CREATE POLICY app_settings_admin_write
    ON public.app_settings
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- Seed the iOS discount at 0 cents so behavior is unchanged until an admin
-- bumps it. Stored as a JSON number for forward-compat with other settings.
INSERT INTO public.app_settings (key, value)
VALUES ('ios_discount_cents', '0'::jsonb)
ON CONFLICT (key) DO NOTHING;
