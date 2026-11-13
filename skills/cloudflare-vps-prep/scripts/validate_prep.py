#!/usr/bin/env python3
"""Validate cloudflare-vps-prep.json and print only masked secrets."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
from pathlib import Path


SCHEMA = "vps-ss-cloudflare-prep/v1"
ACCOUNT_RE = re.compile(r"^[0-9a-fA-F]{32}$")
SUBDOMAIN_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate cloudflare-vps-prep.json")
    parser.add_argument("file", type=Path)
    parser.add_argument("--fix-permissions", action="store_true")
    return parser.parse_args()


def mask(value: str) -> str:
    if len(value) <= 10:
        return "********"
    return f"{value[:4]}...{value[-4:]}"


def require_string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{name} must be a non-empty string")
    return value


def main() -> int:
    args = parse_args()
    path = args.file.expanduser().resolve()
    if args.fix_permissions:
        os.chmod(path, 0o600)

    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        raise SystemExit(f"Unsafe permissions {mode:04o}; run again with --fix-permissions.")

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") != SCHEMA:
            raise ValueError(f"schema must be {SCHEMA}")
        cloudflare = data.get("cloudflare")
        if not isinstance(cloudflare, dict):
            raise ValueError("cloudflare must be an object")
        account_id = require_string(cloudflare.get("account_id"), "cloudflare.account_id")
        subdomain = require_string(cloudflare.get("workers_subdomain"), "cloudflare.workers_subdomain")
        token = require_string(cloudflare.get("api_token"), "cloudflare.api_token")
        if not ACCOUNT_RE.fullmatch(account_id):
            raise ValueError("cloudflare.account_id must be 32 hexadecimal characters")
        if not SUBDOMAIN_RE.fullmatch(subdomain):
            raise ValueError("cloudflare.workers_subdomain has an invalid format")
        if len(token) < 20 or any(char.isspace() for char in token):
            raise ValueError("cloudflare.api_token is too short or contains whitespace")
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"Invalid preparation file: {exc}") from exc

    print(f"Valid: {path}")
    print(f"Account ID: {account_id.lower()}")
    print(f"Workers host: {subdomain}.workers.dev")
    print(f"API token: {mask(token)}")
    print(f"Permissions: {mode:04o}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
