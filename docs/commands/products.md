# rd products

Product catalog. Part of LeadDrive. Run `rd products <verb> --help` for exhaustive flags.

## `rd products list [-j]`

List products, newest first.

| Flag | Purpose |
|---|---|
| `--active` / `--inactive` | filter by active state |
| `--category C` | filter by category |
| `--search Q` | match name, code, or category |
| `--page N` / `--limit N` | pagination (max 100/page) |

```sh
rd products list --active --category Software
rd products list --inactive -j | jq -r '.products[].id'
```

## `rd products get ID [-j]`

Show one product.

## `rd products create --name NAME [-j]`

Create a product. **Idempotent** via `--external-id`.

| Flag | Purpose |
|---|---|
| `--name` | **required** |
| `--code` `--category` `--description` `--price` `--currency` `--tax` `--unit` | attributes |
| `--billing-frequency one_time\|monthly\|quarterly\|annually` `--billing-cycles N` | billing |
| `--visible-to owner\|team\|everyone` `--owner-id ID` | visibility/owner |
| `--active` / `--inactive` | initial state |
| `--external-id` | idempotency key |

```sh
rd products create --name "Pro Plan" --price 99 --currency USD --billing-frequency monthly
```

## `rd products update ID [-j]`

Update a product — same flags as create (provide at least one).

## `rd products activate ID [-j]` · `rd products deactivate ID [-j]`

Flip the `active` flag. (Equivalent to `update --active` / `--inactive`, but explicit verbs.)

## `rd products delete ID --yes`

**Destructive.** Hard delete; requires `--yes`.

## Notes

- Exit `2` if `--name` missing on create, no fields on update, or `--yes` missing on delete.
