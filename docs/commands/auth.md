# rd — auth & session

Managing your API token and identity. Tokens are **organization-scoped**; mint one in the web UI under
**Organization Settings → API**. See the [output contract & config](../../README.md#output-contract) for exit
codes and host/token overrides.

## `rd login [TOKEN]`

Store an API token in `~/.netrc`. With no argument, prompts (hidden input); non-interactive with the token
as an argument or via `RIGHTDESK_TOKEN`. Verifies the token against `/me` after storing.

```sh
rd login                      # prompted, hidden
rd login <token>              # non-interactive
RIGHTDESK_TOKEN=<token> rd whoami   # env override, nothing stored
```

## `rd logout`

Clear the locally stored token. The token stays valid server-side until revoked in the web UI.

## `rd whoami [-j]`

Show the authenticated user + organization. Use `-j` to confirm identity in scripts.

```sh
rd whoami
rd whoami -j | jq -r '.organization.name'
```

## `rd skills`

Print the agent/LLM usage guide (the embedded `skill.md`) to stdout — a condensed, machine-consumable
walkthrough of auth, the output contract, and every command.

## Switching organizations

Tokens are org-scoped. To act in another org, mint a token there and `rd login` again — this overwrites the
local entry. `--host` / `RIGHTDESK_URL` points at a different server (self-hosted or dev).
