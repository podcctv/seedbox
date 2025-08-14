-- Initial database schema for MediaHub (seedbox)
-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT CHECK (role IN ('guest','user','admin')) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Items table
CREATE TABLE IF NOT EXISTS items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    infohash TEXT,
    title TEXT,
    size_bytes BIGINT,
    duration_sec INT NULL,
    source TEXT CHECK (source IN ('bitmagnet','manual')),
    status TEXT CHECK (status IN ('indexed','downloading','staging','processing','ready','failed')),
    preview_key TEXT,
    hls_key TEXT,
    download_path TEXT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Actors & relations
CREATE TABLE IF NOT EXISTS actors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL
);
CREATE TABLE IF NOT EXISTS item_actors (
    item_id UUID REFERENCES items(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES actors(id) ON DELETE CASCADE
);

-- Tags & relations
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT CHECK (type IN ('genre','quality','language','other'))
);
CREATE TABLE IF NOT EXISTS item_tags (
    item_id UUID REFERENCES items(id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tags(id) ON DELETE CASCADE
);

-- Jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID REFERENCES items(id) ON DELETE CASCADE,
    stage TEXT,
    status TEXT,
    payload JSONB,
    log TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
