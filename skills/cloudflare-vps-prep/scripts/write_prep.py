#!/usr/bin/env python3
"""Create a validated Cloudflare preparation file without exposing its token."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path


SCHEMA = "vps-ss-cloudflare-prep/v1"
ACCOUNT_RE = re.compile(r"^[0-9a-fA-F]{32}$")
SUBDOMAIN_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create cloudflare-vps-prep.json")
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--workers-subdomain", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def mask(value: str) -> str:
    if len(value) <= 10:
        return "********"
    return f"{value[:4]}...{value[-4:]}"


def main() -> int:
    args = parse_args()
    account_id = args.account_id.strip()
    subdomain = args.workers_subdomain.strip().lower()
    if subdomain.endswith(".workers.dev"):
        subdomain = subdomain[: -len(".workers.dev")]

    if not ACCOUNT_RE.fullmatch(account_id):
        raise SystemExit("Account ID must be exactly 32 hexadecimal characters.")
    if not SUBDOMAIN_RE.fullmatch(subdomain):
        raise SystemExit("workers.dev subdomain must use lowercase letters, digits, and hyphens.")

    token = getpass.getpass("Cloudflare API token (hidden): ").strip()
    if len(token) < 20 or any(char.isspace() for char in token):
        raise SystemExit("API token is too short or contains whitespace.")

    payload = {
        "schema": SCHEMA,
        "cloudflare": {
            "account_id": account_id.lower(),
            "workers_subdomain": subdomain,
            "api_token": token,
        },
        "metadata": {
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "created_by": "cloudflare-vps-prep",
        },
    }

    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temporary_name, output)
        os.chmod(output, 0o600)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise

    print(f"Created: {output}")
    print(f"Account ID: {account_id.lower()}")
    print(f"Workers host: {subdomain}.workers.dev")
    print(f"API token: {mask(token)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
