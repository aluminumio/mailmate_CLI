# rd

CLI for the [RightDesk](https://app.rightdesk.com) API. The command is `rd`. Crystal binary, distributed via Homebrew and GitHub Releases.

## Install

    brew install aluminumio/tap/rd

Or download a binary from [Releases](https://github.com/aluminumio/rightdesk-cli/releases).

## Grammar

    rd <noun> <verb> [target] [flags]

Nouns are plural, verb second, target positional, flags named — e.g. `rd deals get 42`,
`rd deals list --status open`. The colon form (`rd deals:get 42`) also works.

    rd login [token]                       # store an API token (from the web UI)
    rd logout
    rd whoami [-j]
    rd deals list [--status open|won|lost] [--page N] [--limit N] [-j]
    rd deals get ID [-j]
    rd contacts search QUERY [--company ID] [-j]
    rd contacts get ID [-j]
    rd contacts list [--page N] [--limit N] [-j]
    rd companies list [--search Q] [--industry I] [--page N] [--limit N] [-j]
    rd companies get ID [-j]
    rd companies create --name NAME [--domain --url --industry --phone --city --country \
                        --postal-code --employees --type --description --owner --external-id] [-j]
    rd companies update ID [same flags] [-j]
    rd pipelines list [-j]
    rd pipelines get ID [-j]
    rd skills                              # print agent/LLM usage guide

`rd <noun>` with no verb lists that noun's commands. Run `rd skills` for an LLM-consumable walkthrough.

## Output contract

- **Data on stdout, diagnostics on stderr.** Errors never touch stdout.
- **`-j`/`--json`** emits the raw JSON payload; under `--json`, errors are structured
  (`{"error","code","hint"}`) on stderr.
- **Exit codes:** `0` success · `1` general · `2` usage · `3` auth · `4` not found · `5` insufficient scope.

## Authentication

RightDesk uses static API tokens (no OAuth device flow). Create one in the web UI under
**Organization Settings → API**, then run `rd login` and paste it. Tokens are **organization-scoped** —
to switch orgs, mint a token in the other org and `login` again (this overwrites the local entry).
`logout` clears only the local copy; revoke server-side in the web UI.

## Configuration

| Flag / Variable | Default | Purpose |
|---|---|---|
| `--host <host>` / `RIGHTDESK_URL` | `https://app.rightdesk.com` | API host (override for self-hosted or dev) |
| `--token <t>` / `RIGHTDESK_TOKEN` | (from `~/.netrc`) | API token override (prefer the env var; never pass secrets in argv) |

Tokens are persisted in `~/.netrc`.

## Build from source

    shards install
    shards build --release
    ./bin/rd --help
