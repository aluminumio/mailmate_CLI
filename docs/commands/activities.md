# rd activities

Activities (calls, meetings, tasks, emails, deadlines) attached to CRM records. Part of LeadDrive.
**Read-only** for now — writes (create / mark done / timers) are a later slice. Run
`rd activities <verb> --help` for exhaustive flags.

## `rd activities list [-j]`

List activities, ordered by due date. Each line shows `id  ✓|○ subject (type)  → linked-record`.

| Flag | Purpose |
|---|---|
| `--done true\|false` | filter by completion (omit → all) |
| `--type T` | activity type (call/meeting/email/task/deadline or org-custom) |
| `--assigned-to ID` | filter by assignee user |
| `--deal` `--lead` `--contact` `--company` `--customer` `--partner` | filter by an associated record id |
| `--due-before` `--due-after` | ISO date bounds |
| `--page N` / `--limit N` | pagination (max 100/page) |

```sh
rd activities list --done false --assigned-to 1
rd activities list --deal 52375
rd activities list --due-before 2026-10-01 -j | jq -r '.activities[].subject'
```

## `rd activities get ID [-j]`

Show one activity — subject, type, done, due date, duration + logged minutes, assignee, and the linked
record (`primary_link_type` / `primary_link_name`).

```sh
rd activities get 43240
```

## Notes

- The subject record is resolved server-side (`primary_link_type`/`primary_link_name`) — one of
  deal/lead/customer/partner/contact.
- `total_logged_minutes` aggregates time entries; `duration_minutes` is the planned duration.
