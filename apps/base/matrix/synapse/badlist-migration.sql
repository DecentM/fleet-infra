-- Badlist schema and tables for synapse-spamcheck-badlist module
-- This migration is idempotent (safe to run multiple times)

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
