# RightDesk CLI — Skill

Drive the RightDesk API from the shell. The command is `rd`, grammar `rd <noun> <verb> [target] [flags]`
(the colon form `rd deals:get 42` also works). All data commands accept `-j`/`--json` for
machine-readable output — prefer this when piping or parsing.

## Authentication

RightDesk uses static API tokens (no browser/OAuth flow). Mint a token in the web UI under
**Organization Settings → API**, then:

```sh
rd login            # paste the token (prompted, hidden); stored in ~/.netrc
rd whoami -j        # confirms the current user + organization
rd logout           # clears the local token copy
```

The token is **organization-scoped**: to act in another org, mint a token there and `login` again
(this overwrites the local entry). `logout` only clears the local copy — the token stays valid
server-side until revoked in the web UI.

Non-interactive: `rd login <token>`, or set `RIGHTDESK_TOKEN` (overrides `~/.netrc`).

## Output contract (important for agents)

- **Data on stdout, diagnostics on stderr** — parse stdout only.
- **`-j`/`--json`** emits the raw JSON payload; under `--json`, errors are structured
  `{"error","code","hint"}` on stderr.
- **Exit codes:** `0` ok · `1` general · `2` usage · `3` auth · `4` not found · `5` insufficient scope.
  Branch on these; e.g. exit `3` means run `rd login` and retry.

## Configuration

| Flag / Variable | Default | Purpose |
|---|---|---|
| `--host` / `RIGHTDESK_URL` | `https://app.rightdesk.com` | API host (override for self-hosted or dev) |
| `--token` / `RIGHTDESK_TOKEN` | (from `~/.netrc`) | API token override |

## Command reference

| Command | Purpose | Key options |
|---|---|---|
| `rd login [token]` | Store an API token | — |
| `rd logout` | Clear the local token | — |
| `rd whoami` | Show current user/org | `-j` |
| `rd deals list` | List deals (newest first) | `--status open\|won\|lost`, `--page N`, `--limit N`, `-j` |
| `rd deals get ID` | Show one deal | `-j` |
| `rd contacts list` | List contacts | `--page N`, `--limit N`, `-j` |
| `rd contacts search QUERY` | Search contacts (name/email/phone) | `--company ID`, `-j` |
| `rd contacts get ID` | Show one contact | `-j` |
| `rd contacts create` | Create a contact | `--email` (required), `--first-name`, `--last-name`, `--phone`, `--note`, `--company-id`, `--line-id`, `--line-user-id`, `--whatsapp-number`, `--linkedin-profile`, `--alternative-emails`, `-j` |
| `rd contacts update ID` | Update a contact | same flags as create, `-j` |
| `rd contacts merge PRIMARY_ID` | Merge a duplicate into the primary (**destructive**) | `--duplicate DUP_ID` (required), `--yes` (required) |
| `rd customers list` | List customers | `--status`, `--owner ID`, `--search Q`, `--page N`, `--limit N`, `-j` |
| `rd customers get ID` | Show one customer | `-j` |
| `rd customers create` | Create a customer | `--title` (required), `--contact-id`, `--company-id`, `--owner-id`, `--value`, `--currency`, `--became-date`, `--source`, `--visible-to`, `--status`, `--description`, `--external-id`, `-j` |
| `rd customers update ID` | Update a customer | same flags as create, `-j` |
| `rd customers timeline ID` | Show a customer's history | `-j` |
| `rd partners list` | List partners | `--status`, `--owner ID`, `--partner-type T`, `--search Q`, `--page N`, `--limit N`, `-j` |
| `rd partners get ID` | Show one partner | `-j` |
| `rd partners create` | Create a partner | `--title` (required), `--partner-type`, plus the same flags as customers, `-j` |
| `rd partners update ID` | Update a partner | same flags as create, `-j` |
| `rd partners timeline ID` | Show a partner's history | `-j` |
| `rd companies list` | List companies | `--search Q`, `--industry I`, `--page N`, `--limit N`, `-j` |
| `rd companies get ID` | Show one company | `-j` |
| `rd companies create` | Create a company | `--name` (required), `--domain`, `--url`, `--industry`, `--phone`, `--city`, `--country`, `--postal-code`, `--employees`, `--type`, `--description`, `--owner`, `--external-id`, `-j` |
| `rd companies update ID` | Update a company | same flags as create, `-j` |
| `rd pipelines list` | List pipelines | `-j` |
| `rd pipelines get ID` | Show a pipeline + stages | `-j` |
| `rd pipelines create` | Create a pipeline | `--name` (required), `--entity deal\|lead`, `--description`, `--default`, `--position N`, `-j` |
| `rd pipelines update ID` | Update a pipeline | `--name`, `--description`, `--default`, `--active`, `--inactive`, `--position`, `-j` |
| `rd pipelines delete ID` | Delete a pipeline (**destructive**) | `--yes` (required) |
| `rd stages list` | List a pipeline's stages (by position) | `--pipeline ID` (required), `-j` |
| `rd stages create` | Create a stage | `--pipeline ID` (required), `--name` (required), `--stage-type open\|won\|lost`, `--probability N`, `--rotting-days N`, `--position N`, `--color HEX`, `-j` |
| `rd stages update ID` | Update a stage | `--pipeline ID` (required), same flags as create, `-j` |
| `rd stages reorder` | Set stage order | `--pipeline ID` (required), `--order ID,ID,ID` (required) |
| `rd stages delete ID` | Delete a stage (**destructive**) | `--pipeline ID` (required), `--yes` (required), `--transfer-to STAGE_ID` (needed if the stage holds active deals/leads) |
| `rd products list` | List products | `--active`, `--inactive`, `--category C`, `--search Q`, `--page N`, `--limit N`, `-j` |
| `rd products get ID` | Show one product | `-j` |
| `rd products create` | Create a product | `--name` (required), `--code`, `--category`, `--description`, `--price`, `--currency`, `--tax`, `--unit`, `--billing-frequency`, `--billing-cycles`, `--visible-to`, `--owner-id`, `--external-id`, `--active\|--inactive`, `-j` |
| `rd products update ID` | Update a product | same flags as create, `-j` |
| `rd products activate ID` | Activate a product | `-j` |
| `rd products deactivate ID` | Deactivate a product | `-j` |
| `rd products delete ID` | Delete a product (**destructive**) | `--yes` (required) |
| `rd skills` | Print this guide | — |

## Tips for agentic use

- **Always pass `-j`** when parsing; the human format is unstable.
- **Capture IDs immediately** with `jq -r` (e.g. `rd deals list --status open -j | jq -r '.deals[].id'`).
- **Branch on exit codes**, not on message text. Exit `3` → `rd login` and retry.
