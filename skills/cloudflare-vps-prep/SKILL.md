---
name: cloudflare-vps-prep
description: Configure the Cloudflare account prerequisites for the vps-ss Docker installer through the live dashboard, then generate a validated cloudflare-vps-prep.json file. Use when the user asks to prepare Cloudflare Workers credentials/materials for a VPS, automate the Cloudflare-side setup, or regenerate the installer preparation file.
---

# Cloudflare VPS Preparation

Prepare only the account-level inputs needed by `vps-ss.sh`. The VPS installer creates the actual Worker after it knows the VPS IP, origin port, random WebSocket path, and origin token.

Read [references/schema.md](references/schema.md) before generating the output file.

## Workflow

1. Open the Cloudflare dashboard in the user's requested browser.
2. Hand control to the user for login, password entry, passkeys, 2FA, CAPTCHA, or recovery challenges. Never ask the user to send those credentials in chat.
3. Select the requested Cloudflare account. If there is exactly one account, use it. If multiple accounts exist and the intended one is not clear, ask one concise question before changing anything.
4. Record the account's 32-character Account ID.
5. Inspect the account's Workers configuration:
   - Reuse an existing `workers.dev` subdomain.
   - If none exists, generate a neutral lowercase suggestion such as `vps-ss-<random>` and configure it. Ask only when Cloudflare requires a user-selected value or the suggestion is unavailable.
6. Create a custom API token scoped to the selected account with only the account permission `Workers Scripts Write`. The dashboard may label the older equivalent as `Workers Scripts Edit` or offer the `Edit Cloudflare Workers` template.
7. Immediately before the final action that creates the API token, request the required action-time confirmation. Explain that the token grants persistent permission to create and update Workers in the selected account.
8. Capture the token shown once by Cloudflare. Do not paste the full token into chat or narration.
9. Generate `cloudflare-vps-prep.json` with `scripts/write_prep.py`, set file mode `0600`, and validate it with `scripts/validate_prep.py`.
10. Report the output path, Account ID, workers.dev hostname, masked token, and the upload/install commands. Never print the full token.

## Boundaries

- Do not create or edit the VPS Worker, DNS records, zones, custom domains, Pages projects, billing, subscriptions, or existing applications unless the user separately asks.
- Do not use a Global API Key or request the Cloudflare account password.
- Do not broaden the token to all accounts when a specific account can be selected.
- Do not add IP filtering unless the user supplies the future VPS egress IP and explicitly requests it.
- Stop and explain the blocker if the signed-in user lacks permission to create account API tokens or configure Workers.
- Reuse existing valid prerequisites instead of creating duplicates.

## Generate The File

Use an interactive terminal so the API token is read with hidden input and is not placed in command arguments:

```bash
python3 scripts/write_prep.py \
  --account-id ACCOUNT_ID \
  --workers-subdomain SUBDOMAIN \
  --output /absolute/path/cloudflare-vps-prep.json
```

Then validate it:

```bash
python3 scripts/validate_prep.py /absolute/path/cloudflare-vps-prep.json
```

When running in a Codex projectless chat, place the user-facing JSON in that task's `outputs` directory. Preserve a `0600` mode after copying or moving it.

## Handoff To The VPS

Give commands in this shape, substituting the real host:

```bash
scp cloudflare-vps-prep.json root@VPS_IP:/root/cloudflare-vps-prep.json
ssh root@VPS_IP
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/vps-ss.sh
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/SHA256SUMS
grep ' vps-ss.sh$' SHA256SUMS | sha256sum -c -
chmod +x vps-ss.sh
./vps-ss.sh
```

The installer automatically detects `/root/cloudflare-vps-prep.json`; the user only chooses Cloudflare mode from the number menu.
