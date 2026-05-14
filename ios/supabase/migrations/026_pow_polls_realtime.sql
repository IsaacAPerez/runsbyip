-- Add pow_polls to the realtime publication so iOS clients can listen
-- for the moment a poll closes (winner_name + status flip) and fire the
-- in-app "you won!" celebration banner.

ALTER PUBLICATION supabase_realtime ADD TABLE pow_polls;
