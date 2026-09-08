# rd

CLI for the [RightDesk](https://app.rightdesk.com) API. The command is `rd`. Crystal binary, distributed via Homebrew and GitHub Releases.

## Install

    brew install aluminumio/tap/rd

Or download a binary from [Releases](https://github.com/aluminumio/rightdesk-cli/releases).

## Use

    rd login                       # paste an API token (from the web UI)
    rd whoami [-j]
    rd deals [--status open|won|lost] [--page N] [-j]
    rd deals:show ID [-j]
    rd contacts:search QUERY [--company ID] [-j]
    rd contacts:show ID [-j]
    rd contacts [--page N] [-j]
    rd pipelines [-j]
    rd pipelines:show ID [-j]
    rd skills                      # print agent/LLM usage guide
    rd logout

Pass `-j`/`--json` on any data command for machine-readable output. Run `rd skills` for a walkthrough an LLM/agent can consume directly.

## Authentication

RightDesk uses static API tokens (no OAuth device flow). Create one in the web UI under **Organization Settings → API**, then run `rd login` and paste it. Tokens are **organization-scoped** — to switch orgs, mint a token in the other org and `login` again (this overwrites the local entry). `logout` clears only the local copy; revoke server-side in the web UI.

## Build from source

    shards install
    shards build --release
    ./bin/rd --help

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RIGHTDESK_URL` | `https://app.rightdesk.com` | API host (override for self-hosted or dev) |
| `RIGHTDESK_TOKEN` | (from `~/.netrc`) | API token override |

Tokens are persisted in `~/.netrc`.
