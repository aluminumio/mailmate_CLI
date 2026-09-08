# RightDesk CLI — Skill

Drive the RightDesk API from the shell. The command is `rd`. All data commands accept `-j`/`--json` for machine-readable output — prefer this when piping or parsing.

## Authentication

RightDesk uses static API tokens (no browser/OAuth flow). Mint a token in the web UI under **Organization Settings → API**, then:

```sh
rd login            # paste the token (prompted, hidden); stored in ~/.netrc
rd whoami -j        # confirms the current user + organization
rd logout           # clears the local token copy
```

The token is **organization-scoped**: to act in another org, mint a token there and `login` again (this overwrites the local entry). `logout` only clears the local copy — the token stays valid server-side until revoked in the web UI.

You can also pass the token non-interactively: `rd login <token>`, or set `RIGHTDESK_TOKEN` in the environment (it overrides `~/.netrc`).

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RIGHTDESK_URL` | `https://app.rightdesk.com` | API host (override for self-hosted or dev) |
| `RIGHTDESK_TOKEN` | (from `~/.netrc`) | API token override |

## Command reference

| Command | Purpose | Key options |
|---|---|---|
| `login [token]` | Store an API token | — |
| `logout` | Clear the local token | — |
| `whoami` | Show current user/org | `-j` |
| `deals` | List deals (newest first) | `--status open\|won\|lost`, `--page N`, `-j` |
| `deals:show <id>` | Show one deal | `-j` |
| `contacts` | List contacts | `--page N`, `-j` |
| `contacts:search <query>` | Search contacts (name/email/phone) | `--company <id>`, `-j` |
| `contacts:show <id>` | Show one contact | `-j` |
| `pipelines` | List pipelines | `-j` |
| `pipelines:show <id>` | Show a pipeline + stages | `-j` |
| `skills` | Print this guide (for agents/LLMs) | — |

## Tips for agentic use

- **Always pass `-j`** when you intend to parse output; the human-readable format is unstable.
- **Capture IDs immediately** with `jq -r` (e.g. `rd deals --status open -j | jq -r '.deals[].id'`).
- **Errors are a non-zero exit code + a single line** like `deals failed: HTTP 422 — {"error":...}`. Parse the JSON after the em-dash.
- **Re-authenticate on 401**: a stale/revoked token surfaces as `... failed: not authenticated (HTTP 401)`. Run `rd login` and retry.
