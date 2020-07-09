require "bundler/setup"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"

ENV["PGSLICE_ENV"] = "test"

$url = ENV["PGSLICE_URL"] || "postgres://localhost/pgslice_test"
$conn = PG::Connection.new($url)
$conn.exec <<-SQL
SET client_min_messages = warning;
DROP TABLE IF EXISTS "Posts_intermediate" CASCADE;
DROP TABLE IF EXISTS "Posts" CASCADE;
DROP TABLE IF EXISTS "Posts_retired" CASCADE;
DROP FUNCTION IF EXISTS "Posts_insert_trigger"();
DROP TABLE IF EXISTS "Users" CASCADE;
CREATE TABLE "Users" (
  "Id" SERIAL PRIMARY KEY
);
CREATE TABLE "Posts" (
  "Id" SERIAL PRIMARY KEY,
  "UserId" INTEGER,
  "createdAt" timestamp,
  "createdAtTz" timestamptz,
  "createdOn" date,
  CONSTRAINT "foreign_key_1" FOREIGN KEY ("UserId") REFERENCES "Users"("Id")
);
CREATE INDEX ON "Posts" ("createdAt");
INSERT INTO "Posts" ("createdAt", "createdAtTz", "createdOn") SELECT NOW(), NOW(), NOW() FROM generate_series(1, 10000) n;

DROP TABLE IF EXISTS "sites" CASCADE;
DROP TABLE IF EXISTS "tag_wrap_sites" CASCADE;
DROP TABLE IF EXISTS "sites_to_tag_wrap_sites" CASCADE;
DROP TABLE IF EXISTS "tw_monitored" CASCADE;
DROP TABLE IF EXISTS tw_monitored_intermediate CASCADE;
DROP TABLE IF EXISTS "tw_monitored_retired" CASCADE;
DROP TYPE IF EXISTS BROWSER CASCADE;
DROP TYPE IF EXISTS DEVICE CASCADE;

CREATE TABLE sites (
  id serial PRIMARY KEY,
  name VARCHAR(255),
  display VARCHAR(255),
  settings jsonb,
  dfp_network_id bigint,
  tag_wrap_id VARCHAR(255),
  initial_scan_time TIMESTAMP WITH TIME ZONE,
  recent_scan_time TIMESTAMP WITH TIME ZONE,
  initial_block_time TIMESTAMP WITH TIME ZONE,
  recent_block_time TIMESTAMP WITH TIME ZONE,
  constraint sites_unique unique (name)
);
INSERT INTO sites (name, display, tag_wrap_id, initial_block_time, recent_block_time) VALUES ('test-site', 'test-site', 'test-wrap-site', NOW() - '6 months'::interval, NOW());

CREATE TABLE tag_wrap_sites (
  id serial PRIMARY KEY,
  name VARCHAR(255),
  initial_block_time TIMESTAMP WITH TIME ZONE,
  recent_block_time TIMESTAMP WITH TIME ZONE,
  created_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT tag_wrap_sites_unique UNIQUE (name)
);
INSERT INTO tag_wrap_sites (name, initial_block_time, recent_block_time, created_time)
SELECT COALESCE(tag_wrap_id, lower(name)), initial_block_time, recent_block_time, initial_block_time
FROM sites
WHERE initial_block_time is not null
ORDER by initial_block_time;

CREATE TABLE sites_to_tag_wrap_sites (
  site_id INT NOT NULL references sites(id),
  tw_site_id INT NOT NULL references tag_wrap_sites(id),
  created_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE (site_id, tw_site_id)
);
COMMENT ON TABLE tag_wrap_sites IS 'Scanning sites to tag wrapper tag_wrap_sites mapping table';

INSERT INTO sites_to_tag_wrap_sites
SELECT s.id, tws.id, NOW()
FROM sites s JOIN tag_wrap_sites tws ON COALESCE(s.tag_wrap_id, lower(s.name)) = tws.name
WHERE s.initial_block_time is not null
ORDER by s.initial_block_time;


DROP TYPE IF EXISTS BROWSER CASCADE;
CREATE TYPE BROWSER AS ENUM ('Edge', 'Safari', 'Chrome', 'IE', 'Firefox', 'Other', 'Samsung Internet', 'Chromium');
DROP TYPE IF EXISTS DEVICE CASCADE;
CREATE TYPE DEVICE AS ENUM ('Windows', 'Mac OS X', 'iOS', 'Android', 'Linux', 'Other');

CREATE TABLE tw_monitored (
  id bigserial PRIMARY KEY,
  site_id INT NOT NULL REFERENCES sites(id),
  hour TIMESTAMP WITH TIME ZONE NOT NULL,
  device DEVICE NOT NULL,
  browser BROWSER NOT NULL,
  domain text NOT NULL,
  file_key TEXT NOT NULL,
  place INT NOT NULL,
  CONSTRAINT tw_monitored_unique UNIQUE (site_id, hour, device, browser, file_key, domain)
);

INSERT INTO tw_monitored (site_id, hour, device, browser, domain, file_key, place)
SELECT 1, GENERATE_SERIES(DATE_TRUNC('hour', NOW() - '6 months'::interval), date_trunc('hour', NOW()), '1 hour'),
'iOS', 'Chrome', 'example.com', 'key123', 100;

SQL