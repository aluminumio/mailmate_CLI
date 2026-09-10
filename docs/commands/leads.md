# rd leads

Leads (opportunities that move through a lead pipeline and **convert** into a deal, customer, or partner).
Part of LeadDrive. Run `rd leads <verb> --help` for exhaustive flags.

## `rd leads list [-j]`

List leads, newest first.

| Flag | Purpose |
|---|---|
| `--status S` | new / contacted / qualified / disqualified / converted |
| `--owner ID` `--source S` `--pipeline ID` `--stage ID` | filters |
| `--page N` / `--limit N` | pagination (max 100/page) |

## `rd leads get ID [-j]`

Show one lead — status, value, pipeline/stage, contact/company, converted-deal id, etc.

## `rd leads create --title T [-j]`

Create a lead. If you omit `--pipeline-id`, the org's **default lead pipeline + its first stage** are
assigned automatically.

| Flag | Purpose |
|---|---|
| `--title` | **required** |
| `--contact-id` `--company-id` `--owner-id` `--referral-partner-id` | associations |
| `--value` `--currency` `--expected-close-date` `--source` `--visible-to` `--status` `--description` | attributes |
| `--pipeline-id` `--stage-id` | place explicitly (else defaulted) |
| `--external-id` | idempotency key |

```sh
rd leads create --title "Rolly — Car purchase" --contact-id 157895 --value 32000 --currency USD
```

## `rd leads update ID [-j]`

Update a lead — same flags as create (provide at least one).

## `rd leads delete ID --yes`

**Destructive.** Requires `--yes`.

## `rd leads move ID (--stage STAGE_ID | --unassigned)`

Move a lead to another stage, or `--unassigned` to pull it out of its pipeline. Exactly one is required.

```sh
rd leads move 30038 --stage 309
rd leads move 30038 --unassigned
```

## `rd leads qualify ID [-j]` · `rd leads disqualify ID [--reason TEXT] [-j]`

Set status to `qualified` / `disqualified`. `disqualify` accepts an optional `--reason`.

## `rd leads convert ID --to deal|customer|partner [--pipeline ID] --yes`

**Outward / irreversible.** Requires `--yes`. Converts the lead and marks it `converted`:

- `--to deal` — creates a **Deal** in a deal-type pipeline (`--pipeline ID` optional; defaults to the org's
  oldest deal pipeline). This is how you create a deal from the CLI today.
- `--to customer` — creates a **Customer** (dedupes by the lead's contact).
- `--to partner` — creates a **Partner**.

Re-converting an already-converted lead, or `--to deal` with no deal pipeline available, → **422/exit 1**.

```sh
rd leads convert 30038 --to deal --pipeline 91 --yes
rd leads convert 30038 --to customer --yes
```

## Example: full opportunity flow

```sh
company=$(rd companies create --name ABCD --domain abcd.example.com -j | jq -r '.company.id')
contact=$(rd contacts create --first-name Rolly --email rolly@example.com --company-id "$company" -j | jq -r '.contact.id')
pipe=$(rd pipelines create --name Car --entity lead --default -j | jq -r '.pipeline.id')
s1=$(rd stages create --pipeline "$pipe" --name Enquiry --stage-type open -j | jq -r '.stage.id')
lead=$(rd leads create --title "Rolly — Car" --contact-id "$contact" --pipeline-id "$pipe" --stage-id "$s1" -j | jq -r '.lead.id')
rd leads qualify "$lead"
rd leads convert "$lead" --to deal --yes      # → new Deal
```

## Notes

- Exit `2` if `--title` missing on create, no fields on update, no target on move, or `--to`/`--yes` missing
  on convert. Cross-org `--contact-id`/`--company-id`/`--pipeline-id` → exit `5`.
