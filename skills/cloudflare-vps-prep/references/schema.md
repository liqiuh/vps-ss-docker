# cloudflare-vps-prep.json Schema

The file is a secret-bearing handoff artifact between Cloudflare dashboard setup and `vps-ss.sh`.

## Canonical Shape

```json
{
  "schema": "vps-ss-cloudflare-prep/v1",
  "cloudflare": {
    "account_id": "0123456789abcdef0123456789abcdef",
    "workers_subdomain": "my-workers-name",
    "api_token": "REDACTED"
  },
  "metadata": {
    "created_at": "2026-11-13T00:00:00Z",
    "created_by": "cloudflare-vps-prep"
  }
}
```

## Field Rules

- `schema`: must be exactly `vps-ss-cloudflare-prep/v1`.
- `cloudflare.account_id`: exactly 32 hexadecimal characters.
- `cloudflare.workers_subdomain`: only the account prefix, not the `.workers.dev` suffix; lowercase letters, digits, and interior hyphens; 1-63 characters; it cannot end with a hyphen.
- `cloudflare.api_token`: the secret API token with `Workers Scripts Write` for the selected account. It must not contain whitespace.
- `metadata.created_at`: UTC ISO-8601 timestamp.
- `metadata.created_by`: fixed value `cloudflare-vps-prep`.

Additional fields may be preserved for forward compatibility, but the generator should emit only the canonical fields unless a later schema version defines more.

## Security Invariants

- File mode must be `0600` before delivery.
- Never include the token in chat, screenshots, logs, filenames, command-line arguments, QR codes, or summaries.
- The installer may read the token but must not copy it into `/opt/vps-ss/.env`.
- The user may revoke the token in Cloudflare after all intended VPS installations are complete. A new token is required for later Worker updates.
