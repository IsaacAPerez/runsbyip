-- Add SELECT policies on storage.objects for avatars + chat-media so
-- authenticated upserts can pass through.
--
-- Symptoms: PFP upload returned 400 "new row violates row-level security
-- policy" even though INSERT and UPDATE policies allow the path. Cause:
-- supabase-storage's upsert path (POST with x-upsert: true) needs to know
-- whether the object already exists before deciding INSERT vs UPDATE. That
-- existence check goes through RLS — and these two buckets had no SELECT
-- policy at all, so the check returned "no row" while the underlying row
-- did exist (or the conflict path errored). The buckets are already
-- public: true so public-CDN reads were never affected, but authenticated
-- upserts were.

CREATE POLICY "Anyone can read avatars"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'avatars');

CREATE POLICY "Anyone can read chat media"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'chat-media');
