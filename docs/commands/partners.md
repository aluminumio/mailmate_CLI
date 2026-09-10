# rd partners

Partners (resellers, distributors, referral partners…). Part of LeadDrive. Sibling of
[customers](customers.md) with an extra `--partner-type`. Label field is **`--title`**. Run
`rd partners <verb> --help` for exhaustive flags.

## `rd partners list [-j]`

List partners, newest first.

| Flag | Purpose |
|---|---|
| `--status S` | filter by status |
| `--owner ID` | filter by owner user |
| `--partner-type T` | reseller / distributor / technology_partner / referral_partner |
| `--search Q` | match title |
| `--page N` / `--limit N` | pagination (max 100/page) |

## `rd partners get ID [-j]`

Show one partner.

## `rd partners create --title T [-j]`

Create a partner. **Idempotent** via `--external-id`.

| Flag | Purpose |
|---|---|
| `--title` | **required** (the label) |
| `--partner-type` | reseller / distributor / technology_partner / referral_partner |
| `--contact-id` `--company-id` `--owner-id` | associations |
| `--value` `--currency` `--became-date` `--source` `--visible-to` `--status` `--description` | attributes |
| `--external-id` | idempotency key |

```sh
rd partners create --title "Reseller Co" --partner-type reseller
```

## `rd partners update ID [-j]`

Update a partner — same flags as create (provide at least one).

## `rd partners timeline ID [-j]`

Show a partner's history: activities + notes + created/converted markers, newest first
(`at  type  summary`). `-j` for structured events.

## Notes

- Exit `2` if `--title` missing on create, no fields on update.
