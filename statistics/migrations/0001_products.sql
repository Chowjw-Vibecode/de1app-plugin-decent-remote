-- Existing installations and older clients belong to Decent Remote.
-- Apply once to the deployed v1 database with Wrangler D1 migrations.
ALTER TABLE installations ADD COLUMN product TEXT NOT NULL DEFAULT 'decent_remote'
    CHECK(product IN ('decent_remote','this_cup'));
CREATE INDEX installations_product_last_seen ON installations(product,last_seen);
