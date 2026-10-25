# Merge / Waffel Edition API

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
