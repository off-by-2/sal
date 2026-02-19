-- +goose Up
-- Enable pgcrypto for gen_random_uuid() and gen_random_bytes()
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA public;

-- Enable unaccent for slug generation
CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA public;

-- +goose Down
DROP EXTENSION IF EXISTS unaccent;
DROP EXTENSION IF EXISTS pgcrypto;
