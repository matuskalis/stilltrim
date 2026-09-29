# Name research: Stilltrim

Research by an Opus subagent, 29 Sep 2026. Decision: the app is called **Stilltrim** (chosen by the orchestrating session on the owner's "you decide"). Open check: a trademark search on USPTO and EUIPO in a browser before any App Store submission.

## Competitors (iTunes lookup API, 29 Sep 2026)

| App (current listing name) | Developer | Model | Privacy claim |
|---|---|---|---|
| CleanMy®Phone: Cleanup Storage (formerly Gemini Photos, id 1277110040) | MacPaw Way Ltd | Subscription $4.99/mo, $19.99/yr or $34.99 one-time | "Offline", on-device AI |
| Cleanup: Phone Storage Cleaner | DEEP FLOW SOFTWARE SERVICES (older listings: Codeway) | Weekly subscription, about $5.95 to $11.99/wk or $29.99 to $49.99 lifetime (comparison sites) | "On-device" |
| Slidebox: Photo Cleaner App | Slidebox LLC | Free with ads, yearly or lifetime $19.99 to $49.99 | none stated |
| Swipewipe: Photo Cleaner | MWM | Free with limits, $9.99/wk or $29.99/yr | none stated |
| Remo Duplicate Photos Remover | Remo Software | Free | "Developer does not collect any data" |
| Clever Cleaner: AI CleanUp App | CleverFiles Inc. | Free daily limits, premium $6.99/wk or $39.99 lifetime | On-device |
| Phone Cleaner・Clean Up Storage | Brain Craft Ltd | Free plus in-app purchases | n/a |
| Swipe Photo Cleaner: SwipeWipe | FlashSoft OU | Free plus in-app purchases | n/a |
| Delete Photos: TinyRoll / Unroller | Above AS / Mohamed Makled | Free plus in-app purchases | n/a |
| PhotoDedup, AiCleanerPro, "Local Photo Cleaner", "OfflineClean" | various | mostly subscription | "100% on-device, never leaves your phone" |

Naming patterns:
- "Photo Cleaner" is in almost every subtitle.
- Saturated brand words (iTunes searches for "<word> photo cleaner"): cull (5 apps), sweep (4), prune (3), tidy (3), keep (2), roll (4), swipe (dozens).
- "On-device, photos never leave your phone" is now a common claim. What this app can claim and let anyone verify in its public code: no networking code at all.
- Words nobody in the category uses yet: still, quiet, hush (only on photo-vault apps), trim (only TrimSwipe).

## Candidates

"free" means: .app gives RDAP 404 plus no NS records, .com gives whois "No match" plus no NS records, github.com/<slug> gives 404. "repos" is GitHub repositories with that string in the name. No US, GB or SK App Store search returned an app with the exact name.

| Candidate | .app | .com | github.com/<slug> | repos | Conflicts | Verdict |
|---|---|---|---|---|---|---|
| Stilltrim | free | free | 404 | 0 | none found | clean |
| Hushroll | free | free (old HushRoll Shopify store lapsed) | 404 | 1 (payroll crypto demo) | PPI "HUSH ROLL" industrial roller; QuietRoll (quietroll.app) is an iPhone private media review app with a close meaning; "haš" is Slovak slang for hashish | usable, baggage |
| Hushsweep | free | free | 404 | 0 | "sweep" crowded | usable |
| Hushtrim | free | free | 404 | 0 | Hush & Trim is a lawn-care business | excluded |
| Pruneroll | free | free | 404 | 0 | "prune" crowded | weak |
| Quietcull | free | free | 404 | 0 | band The Quiet Cull; "cull" crowded | weak |
| Hushcull | free | free | 404 | 0 | "cull" crowded | weak |
| Sweeproll | free | registered 2026-02-12 | 404 | 0 | both words crowded | weak |
| Stillroll | free | registered 2025-07-17 | 404 | 3 (photo tools) | overlaps | weak |
| Thinroll | free | registered 2026-01-19 | 404 | 0 | "th" is hard for Slovak speakers | fails constraint |

Rejected: Siftroll (an iPhone camera-roll cleaner repo created 27 Sep 2026, rollsift.app live), Rolltidy (Tidy Roll game, tidy-roll repo, ROLL TIDE® reg. 1335032), Homesweep (App Store toxin scanner), Quietroll (live app), Winnow (org, .app and .com taken), Tidyroll (.app taken), Lintroll (user and .com taken), Pocketcull (.com registered 2026-09-23), Unsent, Airgap, Stayput (taken).

Trademark: not checked. USPTO tmsearch and EUIPO eSearch render only in JavaScript. Only ROLL TIDE® was confirmed, via Justia.

App Store limit: the iTunes Search API shows live listings only. A name reserved in App Store Connect stays invisible until the app record is created.

## Why Stilltrim

Clean on every signal: both domains, GitHub user and repo names, the App Store in 3 regions, a web search. Neither "still" nor "trim" is used much in the category. Reads as "still" (a photograph, and quiet) plus "trim" (the act of cleaning up). Easy for Slovaks (stil-trim). Works as slug and bundle id segment. Weakness: the privacy link is implied, not literal; the subtitle carries it, for example "Stilltrim: Private Photo Cleaner".

Spot-check by the orchestrating session, 29 Sep 2026: `dig +short NS stilltrim.app` and `stilltrim.com` both empty, `https://github.com/stilltrim` gives 404, iTunes search for "stilltrim" returns 0 results.

## Commands used

```
dig +short NS <name>.app ; dig +short NS <name>.com
whois <name>.com | grep -iE "no match|creation date"
curl -sL -o /dev/null -w '%{http_code}' https://rdap.org/domain/<name>.app
curl -s -o /dev/null -w '%{http_code}' https://github.com/<name>
gh api "search/repositories?q=<name>+in:name" --jq '.total_count'
curl -s "https://itunes.apple.com/search?term=<name>&entity=software&country={us,gb,sk}&limit=5" | jq -c '[.resultCount,[.results[].trackName]]'
curl -s "https://itunes.apple.com/search?term=<word>+photo+cleaner&entity=software&country=us&limit=8"
```
