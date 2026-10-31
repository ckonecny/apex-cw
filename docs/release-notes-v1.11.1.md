# APEX CW v1.11.1

Fixes for the straight-key timing analysis of 1.11.0, found in the review before the store release.

## Fixed
- **CW Keyer rhythm panel:** a pause between phrases (thinking, end of a text) counted as a huge word gap and pulled the number down by tens of points. Gaps over 15 dit lengths are now ignored.
- The panel starts afresh when the analysis is switched off or the adapter is unplugged, instead of joining old and new keying.
- **Send:** whether a block counts for the timing history is decided when the block starts; an adapter pulled before the last word no longer drops the block.
- Training goals: no more error for a Koch sequence with a single character.
