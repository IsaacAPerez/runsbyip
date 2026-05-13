-- Global admin-controlled chat send lock. Lives in app_settings so it's
-- editable without a deploy and reachable from realtime. A BEFORE INSERT
-- trigger on public.messages enforces the lock server-side; admins bypass.

INSERT INTO public.app_settings (key, value)
VALUES ('chat_send_locked', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.enforce_chat_send_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_locked boolean;
    v_is_admin boolean;
BEGIN
    SELECT (value = 'true'::jsonb) INTO v_locked
    FROM public.app_settings
    WHERE key = 'chat_send_locked';

    IF NOT COALESCE(v_locked, false) THEN
        RETURN NEW;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    ) INTO v_is_admin;

    IF v_is_admin THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Chat is currently locked by an admin' USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS enforce_chat_send_lock_trigger ON public.messages;
CREATE TRIGGER enforce_chat_send_lock_trigger
    BEFORE INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_chat_send_lock();

-- Make app_settings changes observable so iOS can flip the UI in real time
-- when an admin toggles the lock from another device.
ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;
