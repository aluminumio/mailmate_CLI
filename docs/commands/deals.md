# rd deals

Deals (sales opportunities). Part of LeadDrive. Run `rd deals <verb> --help` for exhaustive flags. A deal can
also be created by converting a lead — see [`rd leads convert`](leads.md#rd-leads-convert-id---to-dealcustomerpartner---yes).

## `rd deals list [-j]`

List deals, newest first (rendered as a table).

| Flag | Purpose |
|---|---|
| `--status open\|won\|lost` | filter by status |
| `--page N` / `--limit N` | pagination (max 100/page) |

```sh
rd deals list --status open
rd deals list --status won -j | jq -r '.deals[] | "\(.id)\t\(.title)"'
```

## `rd deals get ID [-j]`

Show one deal — title, value, stage, pipeline, owner, contact, company, lost_reason, customer/partner links.

## `rd deals create --title T [-j]`

Create a deal. If a pipeline is given, the deal lands on that pipeline's first `open` stage.

| Flag | Purpose |
|---|---|
| `--title` | **required** |
| `--pipeline-id` `--stage-id` | placement |
| `--contact-id` `--company-id` `--owner-id` `--referral-partner-id` | associations |
| `--value` `--currency` `--expected-close-date` `--source` `--visible-to` `--probability` | attributes |

```sh
rd deals create --title "Rolly — Car" --pipeline-id 91 --value 32000 --currency USD
```

## `rd deals update ID [-j]`

Update a deal — same flags as create (provide at least one).

## `rd deals move ID --stage STAGE_ID [-j]`

Move a deal to another stage **in the same pipeline** (cross-pipeline → 422/exit 1). Moving to a `won`/`lost`
stage auto-updates the deal's status.

```sh
rd deals move 52375 --stage 317
```

## `rd deals won ID [-j]` · `rd deals lost ID [--reason TEXT] [-j]` · `rd deals reopen ID [-j]`

Mark a deal won or lost (with an optional reason), or reopen a closed deal back to `open`. These are
reversible, so no `--yes` gate.

```sh
rd deals won 52375
rd deals lost 52375 --reason "went with a competitor"
rd deals reopen 52375
```

## `rd deals convert ID --to customer|partner --yes`

**Outward.** Requires `--yes`. Creates (or links an existing) **Customer** or **Partner** from the deal and
sets `customer_id`/`partner_id` back on it. Idempotent — re-converting returns the existing record.

```sh
rd deals convert 52375 --to customer --yes
```

## `rd deals merge PRIMARY_ID --duplicate DUP_ID --yes`

**Destructive.** Requires `--yes`. Merges `DUP_ID` into `PRIMARY_ID` (primary wins; duplicate soft-deleted,
its relationships transferred). Deals in **different pipelines cannot be merged** → 422/exit 1 (move them to
the same pipeline first).

```sh
rd deals merge 52375 --duplicate 52380 --yes
```

## Notes

- Exit `2` if a required flag is missing (`--title` on create, `--stage` on move, `--to`/`--yes` on convert,
  `--duplicate`/`--yes` on merge). Cross-org contact/pipeline → exit `5`.
- **Not yet:** deal line-items (products) and checklists — a later slice.
