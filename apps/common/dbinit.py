"""One-shot schema + grants for app1 (run by the Helm post-install/upgrade Job as the admin user).

Idempotent: safe to run on every deploy and in every cluster.
"""

import os
import re

from common import db
from common.secrets import read_secret

SEED_ITEMS = [f"item-{i}" for i in range(1, 6)]


def main() -> None:
    app_user = os.environ["APP_DB_USER"]
    if not re.fullmatch(r"[a-z0-9_.@-]+", app_user):
        raise SystemExit(f"Unexpected database user name: {app_user!r}")

    conn = db.connect("pgadmin", password=read_secret(os.environ["ADMIN_PASSWORD_SECRET"]))
    try:
        cur = conn.cursor()
        cur.execute("CREATE SCHEMA IF NOT EXISTS catalog")
        cur.execute(
            "CREATE TABLE IF NOT EXISTS catalog.items ("
            "id SERIAL PRIMARY KEY, name TEXT NOT NULL UNIQUE)"
        )
        for name in SEED_ITEMS:
            cur.execute("INSERT INTO catalog.items (name) VALUES (%s) ON CONFLICT DO NOTHING", (name,))
        cur.execute(f'GRANT USAGE ON SCHEMA catalog TO "{app_user}"')
        cur.execute(f'GRANT SELECT ON catalog.items TO "{app_user}"')
        conn.commit()
        print(f"catalog.items ready; read access granted to {app_user}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
