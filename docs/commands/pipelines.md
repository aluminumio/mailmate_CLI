# rd pipelines

Deal/lead pipelines (the columns a record moves through). Part of LeadDrive. Stages live *inside* a
pipeline — see [`rd stages`](stages.md).

## `rd pipelines list [-j]`

List all pipelines.

## `rd pipelines get ID [-j]`

Show a pipeline **and its stages** (ordered by position).

```sh
rd pipelines get 2
```

## `rd pipelines create --name NAME [-j]`

Create a pipeline.

| Flag | Purpose |
|---|---|
| `--name` | **required** |
| `--entity deal\|lead` | which entity type (create only; immutable after) |
| `--description` | text |
| `--default` | make it the default for its entity type (unsets the previous default) |
| `--position N` | sort position |

```sh
rd pipelines create --name "Car" --entity lead --default
```

## `rd pipelines update ID [-j]`

Update a pipeline: `--name` `--description` `--default` `--active` `--inactive` `--position`.

## `rd pipelines delete ID --yes`

**Destructive.** Requires `--yes`. Fails with **409/exit 1** if the pipeline still has deals or leads —
move or delete those first.

## Notes

- One default per entity type is enforced server-side.
- Exit `2` if `--name` missing on create, no fields on update, or `--yes` missing on delete.
