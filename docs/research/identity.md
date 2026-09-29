# Identity directions for Stilltrim

By an Opus subagent, 29 Sep 2026. Decision by the orchestrating session: direction A, contact sheet. All hex values are placeholders until seen in the Simulator. Drafts in `identity/`: `stilltrim-icon.svg` (A), `stilltrim-icon-alt.svg` (B), `review-sheet.png` (both at 1024, grayscale, 60 px, next to eight competitor icons).

## What competitors do

Real icons pulled from the iTunes Search API: CleanMy Phone, Cleanup, Slidebox, Swipewipe, Clever Cleaner, Remo, Cleaner Kit, Photo Cleaner Guru. Colour: saturated blue, violet or magenta, often a gradient or glossy 3D. Motifs: sparkles, brooms, stacked swipe cards, the mountain-and-sun photo glyph. Exceptions: Slidebox (thin black diamond on white), Remo (yellow on black). Nobody uses red, a photo grid, or a dark field with one solid mass.

## A. Contact sheet (chosen)

Photographers mark keepers on a contact sheet with a red grease pencil. Here the loop marks what goes, deliberately inverted.
- Accent: light #D12E1F (white label 5.1:1). Dark #FF5B47 (white label 3.07:1, large or bold text only, same as Apple's dark red).
- Font: system. Keep `.rounded` on the Home number.
- Icon: near-black field, 3 by 3 grid of grey frames, centre frame lighter and circled by a loose red loop whose ends overlap. At 60 px it reads as "photo grid, one marked"; the loop separates from the frames in grayscale.
- Home: Scan button and category symbols red. Review: selection border and check in the same red as the Delete bar (the mark means "this goes"). Done: Done button red, count in label colour.

## B. Trim marks (monochrome, second)

Printers' trim marks around a print. Accent graphite #1C1D1F light, paper #EDEDED dark. System font, drop `.rounded`. Icon: graphite field, 4:3 paper-white print, two thick marks per corner stopping short of the corner. Weakness: no photographic cue at 60 px. Needs code: black label on dark-mode `borderedProminent` buttons, a dark check glyph (`ReviewView.swift:158`), a double-stroke selection border (`ReviewView.swift:148`).

## C. Cutting mat (concept only, not drawn)

Mat green #1F6B4E light, #3FA37A dark. White still with one edge strip sliced off. Delete stays system red.

## Code notes

Done screen lives in `SettingsView.swift`. Delete is hard-coded `.tint(.red)` in `ReviewView.swift:119`.

## Not checked

iOS 26 icon pipeline (glass treatment, Icon Composer layers, dark and tinted variants). No Simulator run of any colour. Renders made with `qlmanage`; 60 px PNGs are LANCZOS downsamples, not direct rasters.
