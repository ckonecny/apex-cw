# Zork I–III story files

Unmodified copies of the compiled Z-machine version 3 story files from the
`COMPILED/` folder of the historicalsource repositories, released by
Microsoft under the MIT License in November 2025 (see `LICENSE`, identical
in all three repositories). The license covers the code only, not the
"Zork" trademark.

| File | Source | Commit | Release / serial | SHA-1 |
|---|---|---|---|---|
| `zork1.z3` | github.com/historicalsource/zork1 | 97b7b3d | 119 / 880429 | c4f162274869b5433e4b9dfa7ee770fc3b789525 |
| `zork2.z3` | github.com/historicalsource/zork2 | 3da9661 | 63 / 860811 | 6e5415ace76ad235a307a5d4a2e88a8980b9f193 |
| `zork3.z3` | github.com/historicalsource/zork3 | 3ec9ed4 | 25 / 860811 | 0340b09fe05cf3ba0f01c04a7699236e15ab2aed |

Zork I–III by Marc Blank, Dave Lebling, Bruce Daniels and Tim Anderson
(Infocom).

## Map layouts (`zork1_map.json`, `zork2_map.json`, `zork3_map.json`)

Written for this app (not Infocom or fan maps). Rooms and exits come from
the story files; these files only hold hand-placed positions (`rooms`:
object number → [x, y] in layout units), the "visited" attribute
(`touchAttr`), the number of direction properties (`directions`), exits the
story computes in a routine (`extra`: [from, to, direction], taken from the
ZIL source), pairs drawn as a note instead of a line (`jumps`) and free
labels (`labels`). Check a layout with `dart run tool/zmap_svg.dart <id>`;
`test/zmachine/adventure_map_test.dart` checks placement and paths.
