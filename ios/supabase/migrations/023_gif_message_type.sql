-- Allow 'gif' as a message_type. Same attachment requirements as 'photo'.

ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_photo_requires_attachment;

ALTER TABLE messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'photo', 'gif'));

ALTER TABLE messages
  ADD CONSTRAINT messages_attachment_required
  CHECK (
    (message_type = 'text' AND attachment_path IS NULL)
    OR (message_type IN ('photo', 'gif') AND attachment_path IS NOT NULL)
  );
