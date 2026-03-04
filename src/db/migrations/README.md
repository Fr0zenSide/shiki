# Database Migrations

Schema is initialized via `db/init/01-schema.sql` on first boot.

Future schema changes should be added as numbered migration files:
- `001_add_column.sql`
- `002_new_table.sql`

Apply manually: `docker compose exec db psql -U shiki -d shiki -f /path/to/migration.sql`
