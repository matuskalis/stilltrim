# Roadmap after the research round (30 Sep 2026)

Synthesis of the round described in `feature-brief.md`. The raw agent reports stay local. Ranked by value over cost, safety first. Token budget note: no further research waves are planned; every item below is a decision or a small build.

## Shipped in this round

- Screenshot kinds (chats, receipts and tickets, codes, verification codes, maps, web, social, documents, pictures, recordings, Mix), read from a 1,536 px copy with Vision revisions pinned. Classifier V2 passes 36 of 36 constructed cases (V1: 15).
- "Delete N above": deletes only ticked photos the list reported as scrolled past, list returns to where the user was. Tracker uses per-cell geometry, not scroll position bindings (those froze the app).
- Safety: bulk select skips favourites and edited photos; every delete re-checks the photo against the scan and keeps what changed; the section order no longer reorders under the user.
- Privacy tripwire v2: 34 self-tests, a library allow-list on the built binary, OS download hooks denied.
- Copy that matches the code: promise wording, Done sheet, permission path (HIG), plurals, states.
- Tools: `scripts/classify-folder.sh` (classify real screenshots on the Mac), `seed-bulk.sh ... pairs` (long similar list).
- Checked on the simulator: a 349 photo delete leaves the rest of the list in place.

## Build next (ranked)

1. Design step 1 (in flight): photo-independent selection mark, one red, three haptic patterns.
2. Review speed: receipt strip instead of the full Done sheet after every batch, bar v2 with the safer button first, "seen, not just passed" (a dwell time) for Delete above. Biggest lever is fewer groups to inspect: sort by gain, then clear-wins tiers with best-shot work.
3. Home and scan: a hero that says "to review" plus a scope line, a breakdown that works with one accent, one scan progress that never restarts, locked rows while a step runs.
4. Screenshots: a "Select older than" menu per heading and a one-time-code chip (rule 4 unchanged), then the Kinds check (counts-only labelling on the phone) to measure real accuracy.
5. Group layout: pairs and triples as large tiles, the contact-strip header, a consistent radius and spacing token set.
6. Best-shot (measured, see the local best-shot report): rank by the bytes of the still only (today Live Photo video and RAW count as detail), let file size and sharpness vote only when their gap clears a margin and call the rest a "close call", add an eyes-open signal from face landmarks, show a reason line under the group. The 16 of 16 result holds with no new data.
6b. Small fixes from the media-type audit: `delete` should report what vanished, not what was requested; a timeout for a stuck delete (ProRAW); cloud-only screenshots list at 0 bytes and are not counted.
7. Motion: cut, settle, count (spec in the local motion report), after the haptics land.
8. Localization prerequisite for Slovak: String Catalog and real plurals, then a native review.

## Research more, needs a phone first

- Does Apple's Duplicates album catch what identical-copy detection would? One hour on the owner's phone decides whether identical copies are built at all.
- Scan time and memory for screenshots at 1,536 px; the cold start of the accurate text level.
- Optimize Storage behaviour (cloud-only originals, sizes, Best bias).
- Burst, Live Photo and Shared Library deletes: the default fetch returns only a burst's representative, so frames never group, and deleting a representative probably removes the whole stack (unverified). A 15 minute device checklist is in the local media-type report.
- Instruments on a 3,000 pair list.

## Decisions for the owner (recommendation first)

1. Visual direction: the "proof sheet" (film base, tight red loop, system backgrounds kept). Step 1 works for any direction. Judge colours on the phone.
2. Red means "this goes" only (neutral Scan button and Home glyphs). Yes.
3. Keep the filled red Delete button. Yes, one per screen.
4. Two-photo groups as large tiles. Yes.
5. Old screenshots: menu plus chip, rule 4 unchanged (option A), not pre-selection.
6. Sensitive screenshot finder (passwords, recovery phrases, IDs): in scope as its own section, never pre-selected, recovery phrases without a Select button. Yes, later.
7. Identical copies: only after the overlap test above.
8. App Store release: not now. Decides money, launch and the Xcode 27 move (star-rating protection needs the iOS 27 SDK, CI uses Xcode 26.6).
9. Hero wording: "to review", not "can be cleaned".
10. Kinds check as a debug-only screen, counts only. Yes.
11. Hide photos whose original is only in iCloud, after the device check. Yes.
12. Best-shot contender protection: should the photos a Best does not clearly beat start unticked? It protects against a coin-flip Best but a burst of near-identical frames then starts with nothing ticked, which slows review. Shipped as a label only ("Close call"); recommend measuring on real groups first.
13. Best-shot: may the cache hold a few face numbers (eye openness), and may the scan read group members at 1,024 px for it? Recommend yes, numbers only, no images.

## Not doing

Compression and Live Photo to still (writes to the library), contacts and email cleaning, an extra app-side delete confirmation (iOS already asks), a per-photo swipe deck as the main mode, iPad and landscape, anything that needs a network.

## Device checklist (15 minutes, after installing the build)

1. Scan. Open Screenshots: how many headings, how many in Mix, anything filed wrongly? Note the scan time.
2. Similar shots: scroll, tap "Delete N above", confirm the count matches the iOS prompt and the list stays where you were.
3. Blurry and dark: a favourite is marked and not selected by Select all.
4. Edit or favourite a photo in Photos after scanning, then delete from a stale list: it is kept and reported.
5. Delete a few hundred in one batch: the list must stay.
6. Airplane mode: a full scan works.
