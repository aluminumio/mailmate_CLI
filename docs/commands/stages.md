# rd stages

Stages within a pipeline. Part of LeadDrive. **Every stage command requires `--pipeline ID`** — stages are
nested under a pipeline. See [`rd pipelines`](pipelines.md).

## `rd stages list --pipeline ID [-j]`

List a pipeline's stages, ordered by position.

```sh
rd stages list --pipeline 2
```

## `rd stages create --pipeline ID --name NAME [-j]`

Create a stage. Position and win/lost probability are auto-managed server-side (a `won` stage forces 100%,
`lost` forces 0%).

| Flag | Purpose |
|---|---|
| `--pipeline ID` | **required** |
| `--name` | **required** |
| `--stage-type open\|won\|lost` | stage kind (default `open`) |
| `--probability N` | win probability 0–100 |
| `--rotting-days N` `--position N` `--color HEX` | attributes |

```sh
rd stages create --pipeline 2 --name Qualified --stage-type open --probability 25
```

## `rd stages update ID --pipeline ID [-j]`

Update a stage — same flags as create (provide at least one besides `--pipeline`).

## `rd stages reorder --pipeline ID --order ID,ID,ID`

Set the stage order in one call. `--order` is a comma-separated list of stage IDs; positions become 1..n in
that order.

```sh
rd stages reorder --pipeline 2 --order 5,7,3
```

## `rd stages delete ID --pipeline ID --yes [--transfer-to STAGE_ID]`

**Destructive.** Requires `--yes`. An empty stage deletes directly. A stage that still holds active
deals/leads returns **409/exit 1** unless `--transfer-to STAGE_ID` is given — which moves those records to
the target stage first, then deletes.

```sh
rd stages delete 7 --pipeline 2 --yes                 # empty stage
rd stages delete 7 --pipeline 2 --yes --transfer-to 5 # move records, then delete
```

## Notes

- Exit `2` if `--pipeline` is missing on any command, `--name` missing on create, `--order` missing on
  reorder, or `--yes` missing on delete.
