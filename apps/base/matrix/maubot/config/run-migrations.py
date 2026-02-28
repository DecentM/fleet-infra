"""
CommunityBot database migrations.

Runs CREATE TABLE IF NOT EXISTS for the three tables used by the
maubot-communitybot plugin (upgrade_table v1–v3).

Connection is read from environment variables:
  - MAUBOT_DB_URI  (full postgres:// URI), or
  - PGHOST / PGPORT / PGDATABASE / PGUSER / PGPASSWORD
"""

import asyncio
import os
import sys
from urllib.parse import urlparse

MIGRATIONS = [
    (
        "user_events",
        """
        CREATE TABLE IF NOT EXISTS user_events (
            mxid TEXT PRIMARY KEY,
            last_message_timestamp BIGINT NOT NULL,
            ignore_inactivity INT
        )
        """,
    ),
    (
        "redaction_tasks",
        """
        CREATE TABLE IF NOT EXISTS redaction_tasks (
            event_id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL
        )
        """,
    ),
    (
        "verification_states",
        """
        CREATE TABLE IF NOT EXISTS verification_states (
            dm_room_id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            target_room_id TEXT NOT NULL,
            verification_phrase TEXT NOT NULL,
            attempts_remaining INTEGER NOT NULL,
            required_power_level INTEGER NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """,
    ),
]


def parse_connection_params() -> dict:
    """Build asyncpg connect kwargs from environment variables."""
    uri = os.environ.get("MAUBOT_DB_URI", "")

    if uri:
        # Normalise the scheme — asyncpg expects "postgresql" but configs
        # often use "postgres".
        if uri.startswith("postgres://"):
            uri = "postgresql://" + uri[len("postgres://"):]

        parsed = urlparse(uri)
        # Strip query params (e.g. ?sslmode=disable) — asyncpg handles SSL
        # through its own keyword arguments.
        return {
            "host": parsed.hostname,
            "port": parsed.port or 5432,
            "database": parsed.path.lstrip("/").split("?")[0],
            "user": parsed.username,
            "password": parsed.password,
        }

    return {
        "host": os.environ.get("PGHOST", "localhost"),
        "port": int(os.environ.get("PGPORT", "5432")),
        "database": os.environ.get("PGDATABASE", "maubot"),
        "user": os.environ.get("PGUSER", "maubot"),
        "password": os.environ.get("PGPASSWORD", ""),
    }


async def run_migrations() -> None:
    params = parse_connection_params()
    dsn_display = f"{params['user']}@{params['host']}:{params['port']}/{params['database']}"
    print(f"Connecting to {dsn_display} ...")

    try:
        import asyncpg
    except ImportError:
        print("ERROR: asyncpg is not installed. Install it with: pip install asyncpg")
        sys.exit(1)

    try:
        conn = await asyncpg.connect(**params)
    except Exception as exc:
        print(f"ERROR: Failed to connect to database: {exc}")
        sys.exit(1)

    try:
        for table_name, ddl in MIGRATIONS:
            print(f"  Creating table {table_name} (if not exists) ...")
            await conn.execute(ddl)
            print(f"  ✓ {table_name}")
    except Exception as exc:
        print(f"ERROR: Migration failed: {exc}")
        sys.exit(1)
    finally:
        await conn.close()

    print("All CommunityBot migrations applied successfully.")


if __name__ == "__main__":
    asyncio.run(run_migrations())
