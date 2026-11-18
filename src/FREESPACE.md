# ROM space ledger

**Every byte HUSH writes to the ROM must be inside a region listed here.**
This covers both free space (new code/data) and hook sites (vanilla bytes we
overwrite). `tools/check_freespace.py` fails the build if:

- an `org` in `src/**/*.asm` is not inside a listed region,
- any byte that differs between `rom/vanilla.sfc` and `build/hush.sfc` is not
  inside a listed region,
- two listed regions overlap,
- `freecode` / `freedata` / `freespace` is used (automatic allocation is banned).

Only the `engine` agent edits this file. Add the row in the same change that
adds the `org`.

## Format

The parser reads the table below. Keep the column order and use `$BBAAAA`
LoROM SNES addresses (inclusive range). Type is `free` or `hook`.

| Start | End | Type | Owner file | Purpose |
|---|---|---|---|---|

## Notes

- Vanilla US 1.0 is a 1 MiB LoROM. Before claiming "free" space, prove it is
  unused: check the region is `$FF`/`$00` fill in `rom/vanilla.sfc` and that
  nothing in `vendor/usdasm/` references it. Record that evidence in the
  Purpose column or a note below.
- Hook rows: put the original bytes/instructions in the hook file's header
  comment (see `src/hooks/README.md`).
- The header checksum is not fixed up (`--fix-checksum=off`). If a release
  needs it, add `$00FFDC-$00FFDF` as a `hook` row at M5.

## Ledger history

_(empty; no space claimed yet)_
