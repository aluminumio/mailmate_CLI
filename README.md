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
    rd contacts create --email EMAIL [--first-name --last-name --phone --note --company-id \
                       --line-id --line-user-id --whatsapp-number --linkedin-profile --alternative-emails] [-j]
    rd contacts update ID [same flags] [-j]
    rd contacts merge PRIMARY_ID --duplicate DUP_ID --yes
    rd customers list [--status S] [--owner ID] [--search Q] [--page N] [--limit N] [-j]
    rd customers get ID [-j]
    rd customers create --title T [--contact-id --company-id --owner-id --value --currency \
                        --became-date --source --visible-to --status --description --external-id] [-j]
    rd customers update ID [same flags] [-j]
    rd customers timeline ID [-j]
    rd partners list [--status S] [--owner ID] [--partner-type T] [--search Q] [--page N] [--limit N] [-j]
    rd partners get ID [-j]
    rd partners create --title T [--partner-type --contact-id --company-id --owner-id --value --currency \
                       --became-date --source --visible-to --status --description --external-id] [-j]
    rd partners update ID [same flags] [-j]
    rd partners timeline ID [-j]
    rd companies list [--search Q] [--industry I] [--page N] [--limit N] [-j]
    rd companies get ID [-j]
    rd companies create --name NAME [--domain --url --industry --phone --city --country \
                        --postal-code --employees --type --description --owner --external-id] [-j]
    rd companies update ID [same flags] [-j]
    rd pipelines list [-j]
    rd pipelines get ID [-j]
    rd pipelines create --name NAME [--entity deal|lead] [--description] [--default] [--position N] [-j]
    rd pipelines update ID [--name --description --default --active --inactive --position] [-j]
    rd pipelines delete ID --yes
    rd stages list --pipeline ID [-j]
    rd stages create --pipeline ID --name NAME [--stage-type open|won|lost] [--probability N] \
                     [--rotting-days N] [--position N] [--color HEX] [-j]
    rd stages update ID --pipeline ID [same flags] [-j]
    rd stages reorder --pipeline ID --order ID,ID,ID
    rd stages delete ID --pipeline ID --yes [--transfer-to STAGE_ID]
    rd products list [--active|--inactive] [--category C] [--search Q] [--page N] [--limit N] [-j]
    rd products get ID [-j]
    rd products create --name NAME [--code --category --description --price --currency --tax --unit \
                       --billing-frequency --billing-cycles --visible-to --owner-id --external-id \
                       --active|--inactive] [-j]
    rd products update ID [same flags] [-j]
    rd products activate ID [-j]
    rd products deactivate ID [-j]
    rd products delete ID --yes
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
