# Auth database schema

`auth_schema.sql` contains only the schema for the authentication `users` table and its indexes.

It intentionally contains **no real user records**, Gmail addresses, Google `sub` values, password hashes, or other test data.

Normally teammates do **not** need to import this file manually because `docker-compose.auth.yml` already mounts `auth-server/db/init.sql` and initializes a fresh PostgreSQL volume automatically on first startup. This copy is included as a portable database-structure reference and handoff artifact.
