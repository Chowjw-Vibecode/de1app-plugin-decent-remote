-- Preserve installation identity, counts and timestamps. Existing versions remain unknown.
ALTER TABLE installations ADD COLUMN version TEXT
    CHECK(version IS NULL OR (length(version)>0 AND length(version)<=64));
