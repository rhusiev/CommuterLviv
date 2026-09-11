-- `/api/status` reports client counts, frame and byte totals and engine health.
-- That is operator data behind a user-shaped gate, so it needs a flag of its
-- own: being signed in is not the same as being the person running the thing.
ALTER TABLE users ADD COLUMN operator boolean NOT NULL DEFAULT false;
