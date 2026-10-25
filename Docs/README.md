# Merge / Waffel Edition API

- `MMExtension_MMMerge.htm`: the MMExtension v2.3 help with everything below merged into
  its sections, plus corrections of the original and the entries it was missing (listed at
  the end of the page under "Changes to the original help"). Works on its own.
- `WaffelEditionAPI.htm`: only the MMMerge / Waffel Edition part.

`WaffelEditionAPI.htm` documents what MMMerge and the Waffel Edition add on top of the
MMExtension help: events, `Merge.Functions`, structures and Lua tables on `Game`, and the
data tables in `Data/Tables`.

Links marked as base help point into `MMExtension.htm`. Put `WaffelEditionAPI.htm` next to
that file (it ships with the game in `ExeMods/MMExtension/`) so those links work.

## Rebuilding

The page is generated from `api-src`:

```
cd Docs/api-src
MMEXT_HELP=path/to/MMExtension.htm python3 gen.py ../WaffelEditionAPI.htm
```

`gen.py` takes the page head and styles from `MMExtension.htm` (set `MMEXT_HELP` or place a
copy next to `gen.py`). Entries live in `entries_*.py` as `GROUPS` lists, one group per
script file and kind (`events`, `functions`, `structs`, `tables`); add or edit entries there.

The merged help is built from the original help and the same entries:

```
cd Docs/api-src
python3 structtypes.py ../..          # refresh mergestructs.json from Structs/*.lua
MMMERGE_REPO=../.. python3 merge.py path/to/MMExtension.htm ../MMExtension_MMMerge.htm
```

`merge.py` also holds the fixes of the original help; it stops with a message if one of
them no longer matches (for example after a new MMExtension version).
