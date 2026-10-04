"""Cloud SQL (PostgreSQL) access over private IP using the Cloud SQL Python Connector."""

import os

_connector = None


def _get_connector():
    global _connector
    if _connector is None:
        from google.cloud.sql.connector import Connector

        _connector = Connector(refresh_strategy="lazy")  # lazy: no background threads before gunicorn forks
    return _connector


def enabled() -> bool:
    return bool(os.getenv("CLOUDSQL_CONNECTION_NAME"))


def connect(user: str, password: str | None = None):
    """IAM database auth when no password is given (the Workload Identity service account logs in)."""
    return _get_connector().connect(
        os.environ["CLOUDSQL_CONNECTION_NAME"],
        "pg8000",
        user=user,
        password=password,
        db=os.environ["DB_NAME"],
        enable_iam_auth=password is None,
        ip_type="PRIVATE",
        timeout=3,
    )
