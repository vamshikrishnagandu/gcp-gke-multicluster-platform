"""Secret Manager helper (Workload Identity; values never touch the image, manifest or env)."""


def read_secret(version_name: str) -> str:
    from google.cloud import secretmanager

    client = secretmanager.SecretManagerServiceClient()
    return client.access_secret_version(name=version_name).payload.data.decode()
