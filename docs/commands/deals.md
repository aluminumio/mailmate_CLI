# rd deals

Deals (sales opportunities). Part of LeadDrive. **Read-only today** — deal *writes* (create/update/move/
won/lost/convert/merge) are on the roadmap. To create a deal now, convert a lead: see
[`rd leads convert`](leads.md#rd-leads-convert-id---to-dealcustomerpartner---yes).

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

Show one deal — title, value, stage, pipeline, owner, contact, company.

```sh
rd deals get 42
rd deals get 42 -j | jq '.deal.value'
```
