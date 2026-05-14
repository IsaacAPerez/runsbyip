-- Storage RLS used a case-sensitive comparison between `auth.uid()::text`
-- (lowercase) and the user-folder segment of the upload path. Older iOS
-- builds (and a thin window of new ones) uploaded with Swift's uppercase
-- uuidString, which RLS then rejected with "new row violates row-level
-- security policy for table objects" — surfacing in the UI as avatar /
-- profile-pic save failures. Lowercase both sides defensively. Also
-- scope the policies to the authenticated role so they're consistent
-- with the chat-media policies.

-- avatars
DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;

CREATE POLICY "Users can upload own avatar"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'avatars'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

CREATE POLICY "Users can update own avatar"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'avatars'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    )
    WITH CHECK (
        bucket_id = 'avatars'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

CREATE POLICY "Users can delete own avatar"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'avatars'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

-- chat-media: same backwards-compat fix so older builds (which uploaded
-- with uppercase uuid before the iOS lowercase fix landed) can still post.
DROP POLICY IF EXISTS "Authenticated users can upload chat media" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own chat media" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own chat media" ON storage.objects;

CREATE POLICY "Users can upload own chat media"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'chat-media'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

CREATE POLICY "Users can update own chat media"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'chat-media'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    )
    WITH CHECK (
        bucket_id = 'chat-media'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

CREATE POLICY "Users can delete own chat media"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'chat-media'
        AND lower((auth.uid())::text) = lower((storage.foldername(name))[1])
    );

-- profiles: clean up the duplicate "Users can update own profile" pair
-- (there were two policies with identical USING that pre-dated a rename).
-- Keep one canonical policy plus the admin-mute carve-out.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Profiles are publicly readable" ON public.profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;

CREATE POLICY "Profiles are readable"
    ON public.profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);
