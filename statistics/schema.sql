-- No raw IP, device identity, account information, or coffee data.
CREATE TABLE IF NOT EXISTS installations (
    id_hash TEXT PRIMARY KEY CHECK(length(id_hash) = 64),
    country TEXT NOT NULL CHECK(length(country) = 2),
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS installations_last_seen ON installations(last_seen);
