# rd customers

Customers (post-conversion accounts). Part of LeadDrive. The label field is **`--title`** (there is no
`name`). Usually created by converting a lead ([`rd leads convert --to customer`](leads.md)), but direct
creation is supported. Run `rd customers <verb> --help` for exhaustive flags.

## `rd customers list [-j]`

List customers, newest first.

| Flag | Purpose |
|---|---|
| `--status S` | filter by status (active/inactive/converted) |
| `--owner ID` | filter by owner user |
| `--search Q` | match title |
| `--page N` / `--limit N` | pagination (max 100/page) |

## `rd customers get ID [-j]`

Show one customer.

## `rd customers create --title T [-j]`

Create a customer. **Idempotent** via `--external-id`.

| Flag | Purpose |
|---|---|
| `--title` | **required** (the label) |
| `--contact-id` `--company-id` `--owner-id` | associations |
| `--value` `--currency` `--became-date` `--source` `--visible-to` `--status` `--description` | attributes |
| `--external-id` | idempotency key |

```sh
rd customers create --title "ABCD Corp" --contact-id 157895 --value 32000 --currency USD
```

## `rd customers update ID [-j]`

Update a customer — same flags as create (provide at least one).

## `rd customers timeline ID [-j]`

Show a customer's history: activities + notes + created/converted markers, newest first
(`at  type  summary`). Use `-j` for structured events.

```sh
rd customers timeline 42
rd customers timeline 42 -j | jq -r '.events[] | "\(.at)\t\(.type)"'
```

## Notes

- One customer per contact is enforced server-side (a second → **422/exit 1**).
- Cross-org `--contact-id`/`--company-id` → exit `5` (forbidden). Exit `2` if `--title` missing on create.
