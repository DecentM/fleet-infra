-- Create schema for badlist tables
CREATE SCHEMA IF NOT EXISTS badlist;

-- Table for IWF link blocklist
CREATE TABLE IF NOT EXISTS badlist.iwf_links (
    url TEXT PRIMARY KEY NOT NULL
);

-- Table for IWF MD5 hash blocklist
CREATE TABLE IF NOT EXISTS badlist.iwf_md5 (
    md5 TEXT PRIMARY KEY NOT NULL
);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_iwf_links_url ON badlist.iwf_links(url);
CREATE INDEX IF NOT EXISTS idx_iwf_md5_md5 ON badlist.iwf_md5(md5);

-- =============================================================================
-- PLACEHOLDER ENTRIES FOR AHO-CORASICK AUTOMATON INITIALIZATION
-- =============================================================================
-- The synapse_spamcheck_badlist module uses an Aho-Corasick automaton for
-- efficient multi-pattern matching. The automaton MUST have at least one entry
-- to initialize properly.
--
-- These placeholder entries use RFC 2606 reserved domains (*.invalid) and
-- zeroed hashes that will NEVER match real content, but allow the module to
-- start successfully.
--
-- IMPORTANT: Replace these with real IWF/NCMEC CSAM blocklists when available.
--
-- To update with real lists:
--   1. Automated sync: Set up a cron job or Kubernetes CronJob to fetch lists
--      from IWF/NCMEC APIs and insert into these tables
--   2. Manual update: Connect to the database and run INSERT statements
--      Example: INSERT INTO badlist.iwf_links (url) VALUES ('actual-blocked-url');
--
-- The module pulls updates every 600 seconds (see pull_from_db_every_sec config)
-- =============================================================================

INSERT INTO badlist.iwf_links (url) 
VALUES ('https://example.invalid/placeholder-for-automaton-init')
ON CONFLICT (url) DO NOTHING;

INSERT INTO badlist.iwf_md5 (md5) 
VALUES ('00000000000000000000000000000000')
ON CONFLICT (md5) DO NOTHING;
