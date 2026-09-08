# rightdesk

CLI for the [RightDesk](https://app.rightdesk.com) API. Crystal binary, distributed via Homebrew and GitHub Releases.

## Install

    brew install aluminumio/tap/rightdesk

Or download a binary from [Releases](https://github.com/aluminumio/rightdesk-cli/releases).

## Use

    rightdesk login                       # paste an API token (from the web UI)
    rightdesk whoami [-j]
    rightdesk deals [--status open|won|lost] [--page N] [-j]
    rightdesk deals:show ID [-j]
    rightdesk contacts:search QUERY [--company ID] [-j]
    rightdesk contacts:show ID [-j]
    rightdesk contacts [--page N] [-j]
    rightdesk pipelines [-j]
    rightdesk pipelines:show ID [-j]
    rightdesk skills                      # print agent/LLM usage guide
    rightdesk logout

Pass `-j`/`--json` on any data command for machine-readable output. Run `rightdesk skills` for a walkthrough an LLM/agent can consume directly.

## Authentication

RightDesk uses static API tokens (no OAuth device flow). Create one in the web UI under **Organization Settings → API**, then run `rightdesk login` and paste it. Tokens are **organization-scoped** — to switch orgs, mint a token in the other org and `login` again (this overwrites the local entry). `logout` clears only the local copy; revoke server-side in the web UI.

## Build from source

    shards install
    shards build --release
    ./bin/rightdesk --help

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RIGHTDESK_URL` | `https://app.rightdesk.com` | API host (override for self-hosted or dev) |
| `RIGHTDESK_TOKEN` | (from `~/.netrc`) | API token override |

Tokens are persisted in `~/.netrc`.
