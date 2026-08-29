# Flong, product and technical specification

Version 1.0, 29 August 2026.

This page is the reference every other document defers to. `CLAUDE.md` holds the working conventions, `README.md` the public presentation, and `docs/technical/` the detail of one subject at a time. When any of them disagrees with this page, this page wins.

---

## 1. Summary

Flong is a feed reader for iOS, iPadOS and macOS. There is no server, no account to create, no hosting. The data lives on the user's devices and propagates through their private CloudKit database.

The product rests on three commitments.

**A clean split between library and stream.** The stream is a disposable cache, rebuildable at any time from the sources. The library is what the user chose to keep : frozen, retained, enriched and synchronized. An article enters the library only on a decision, explicit or by rule.

**Search that is genuinely indexed.** A local full-text index over the whole corpus, a query language with operators, and semantic search over the library.

**Enrichment entirely on device.** Classification, tagging and summaries by the system model, without any content leaving the device.

---

## 2. Goals and non-goals

### Goals

- Read several hundred feeds comfortably and offline.
- Find any article read years ago, instantly.
- Keep what matters for good, including after the source disappears.
- Automate sorting through deterministic rules, replayable over history.
- Depend on no third-party service to function.

### Non-goals

- Server, account, multi-user, social sharing.
- Web client, Android client.
- Permanent freshness and notification on publication.
- Receiving e-mail, full read-it-later of the Wallabag kind, collaborative annotation.
- Remote access by an agent from another machine.

---

## 3. Platforms and requirements

| Platform | Minimum version | Role |
| -------- | --------------- | ---- |
| iOS and iPadOS | 26 | complete |
| macOS | 26 | complete |

An active iCloud account is required for synchronization, but not for operation : Flong stays fully usable on a single device without iCloud.

**No device is required.** An iPhone on its own must be able to perform a complete cold start, import included, with no other device on the account. No feature exists on macOS alone. The Mac brings comfort, never an exclusive capability.

---

## 4. Concepts

**Feed** : a source of articles, identified by a canonical URL. Public or private.

**Article** : an entry in a feed, identified stably by its GUID, or failing that by the pair of link and publication date.

**Reading stream** : the set of articles present locally, unread and recently read. A local cache, bounded in age and volume, never synchronized, rebuildable.

**Library** : the set of retained articles. Content frozen at the moment of promotion, synchronized, never purged.

**Tag** : a namespaced label, for example `veille/ios`, applicable to articles and to feeds. A folder is only a view over a root tag.

**Rule** : a condition expressed in the query language, paired with a list of actions.

**Saved query** : a named query, reusable as a view, as a rule condition, or as the source of a widget.

---

## 5. Architecture

A single application, shared code, distinct interface layers per platform.

| Module | Responsibility |
| ------ | -------------- |
| `Fetcher` | outgoing requests, HTTP conditionality, politeness, scheduling |
| `Parser` | RSS, Atom, JSON Feed, h-feed, normalization |
| `Sanitizer` | whitelist-based HTML sanitization |
| `Extractor` | full-text extraction, reader mode |
| `Store` | SQLite through GRDB, migrations, purge |
| `Indexer` | FTS5 for the stream, Core Spotlight for the library |
| `Search` | The query language, and its compilation to SQL |
| `Enricher` | vectors, classification, rule execution |
| `Sync` | `CKSyncEngine` on the private database |
| `Automation` | App Intents, widgets, local MCP server on macOS |
| `Import` | OPML and service imports, exports |

SQLite is driven directly through GRDB. SwiftData is ruled out : the volume is large, the concurrency needs fine control, and FTS5 virtual tables need direct access.

GRDB is the only external dependency, and it stays that way. A package is added only where writing the equivalent ourselves would be unreasonable ; everything else comes from the system frameworks.

---

## 6. Local data model

| Table | Contents |
| ----- | -------- |
| `feed` | canonical URL, title, folder, conditionality metadata (`etag`, `last_modified`), health, observed periodicity, local settings |
| `entry` | stream article, stable identifier, metadata, read state, reception date |
| `entry_body` | sanitized body, extracted body, normalized plain text |
| `entry_fts` | FTS5 virtual table, contentless, kept in step by triggers |
| `library_item` | retained article, frozen content, annotations, vector, model identifier and revision |
| `tag`, `tag_binding` | tags and assignments |
| `rule` | condition, actions, order, enabled state |
| `saved_query` | named queries |
| `read_state_block` | read states, compacted into one row per period |
| `sync_state` | `CKSyncEngine` tokens |

Technical keys are UUIDv7, for natural temporal ordering and lightly fragmented indexes.

Database data protection in the "after first unlock" class, which is what makes background work possible.

---

## 7. Synchronization

The private CloudKit database only, through `CKSyncEngine`. No hand-written synchronization : the engine takes care of ordering, notification subscriptions, batching, errors and resumption.

### Record budget

This is the dominant design constraint. CloudKit degrades on record count and change throughput, not on byte volume. A bulk push of tens of thousands of records triggers validation size errors, then durable rate limiting.

| Record type | Over three years | Contents |
| ----------- | ---------------- | -------- |
| feeds, folders, tags, rules, queries, settings | a few hundred | complete |
| library items | 1,000 to 2,500 | frozen content, tags, annotations, vector |
| read-state blocks | a few dozen | compressed sets of fingerprints, one per month |
| catch-up headers | a few hundred, sliding | metadata only |
| **target total** | **around 3,000** | |

For comparison, one record per article would mean more than a hundred thousand records over the same period.

### Read-state compaction

One record per month, holding the compressed set of short fingerprints of the articles read in it.

Per month, and not per feed and per month : a reader following three hundred feeds would otherwise write three hundred records a month, which the budget above exists to prevent. A month of a heavy reader is a few tens of kilobytes, well inside one record.

A fingerprint is eight bytes of a digest of the feed address and the article's own identity, which two devices work out to the same value without ever having spoken. Local identifiers cannot travel ; these can.

Starred articles are not in these blocks. Being starred is what puts an article in the library, and a library item is a record with a real deletion, so it travels as itself. A set of fingerprints only grows, and unstarring would have nowhere to go in it.

Merging is a union, so the operation is commutative and idempotent. There is no conflict resolution logic to write, which removes the main source of bugs in multi-device synchronization. It follows that reading is one way : marking an article unread is a local decision and does not travel. That is the price of having no conflict resolution at all, and it is worth paying.

### Catch-up headers

A device left switched off for several days misses the articles already dropped from their feeds. A bounded mechanism answers it : one record per feed and per day, holding identifiers, titles, links and dates only, over a sliding thirty-day window, purged automatically. The late device knows what it missed and can retry fetching it from the source.

The feature can be turned off, and its cost is capped by the window.

### What never transits

Stream article bodies, indexes, vectors of articles that were not retained, secrets, any log.

### Quotas and errors

Private database storage counts against the user's iCloud quota, whose free tier is 5 GB. CloudKit returns `quotaExceeded`, which the application presents itself along with an offered purge.

Rate limiting does not always come as `requestRateLimited` : `serviceUnavailable`, code 6, HTTP 503, is the frequent case in practice. Both are handled, honouring `CKErrorRetryAfterKey` and falling back to exponential backoff.

---

## 8. Collection

Every device collects on its own behalf.

**Accepted formats** : RSS 0.9x, 1.0 and 2.0, Atom 1.0, JSON Feed 1.1, h-feed microformats2. Automatic discovery through `<link rel="alternate">`, with a fallback on the usual locations.

**Adding a feed** : by URL, by pasting a page address, through the Share extension, by OPML import, by drag and drop on macOS.

**HTTP conditionality**, always :

- `If-None-Match` and `If-Modified-Since` on every request ;
- the 304 rate tracked as a health indicator, surfaced in the feed settings ;
- `Accept-Encoding` gzip and brotli.

**Politeness** :

- a token bucket per host name, not per feed ;
- `Retry-After` honoured, exponential backoff with jitter ;
- quarantine after repeated failures, with a notification and an offer to fix or delete ;
- an identifying user agent, carrying the project URL ;
- a response size cap and strict timeouts.

**Scheduling** : an interval derived from the median of the observed publication gaps, bounded between fifteen minutes and twenty-four hours, corrected by time of day for sources publishing on business hours. Manual per-feed override.

**Device stagger** : several devices of the same user polling the same feeds multiply the traffic reaching publishers. A pseudo-random stagger derived from the device identifier answers it, together with skipping the automatic refresh on a device brought to the foreground for less than a few seconds.

**Network** : an option to restrict to Wi-Fi, an option to suspend in Low Power Mode, a configurable monthly cellular data cap.

**Actual triggers** : on return to the foreground, on a refresh gesture, and opportunistically in the background when the system allows it.

---

## 9. Private and authenticated feeds

**In scope** : a per-subscriber secret URL, the dominant case among subscription platforms, HTTP Basic authentication, bearer token or fixed header.

**Out of scope** : cookie sessions, form authentication, OAuth, extraction behind a paywall. These break constantly and do not deliver enough to justify their cost.

**Secret storage** : the keychain exclusively, with the appropriate protection class, propagated between devices by iCloud Keychain. Never in the database, never in CloudKit, never in a log.

A secret URL is treated as a secret in its own right : masked in the interface, redacted from exports by default, absent from error messages.

**Export** : two explicit modes, redacted by default with a marker forcing re-entry at import time, or complete on a deliberate action with a warning.

**Failures** : a 401 or a 403 quarantines that one feed, with a notification and polling stopped after three consecutive failures, so dead credentials are not hammered at the publisher.

**Newsletters** : the real channel of paid subscriptions remains e-mail. Flong does not receive mail. The application documents and eases the setup of a third-party e-mail-to-feed service, which provides an address and an Atom feed per newsletter. The dependency is flagged as such in the interface and is never mandatory.

---

## 10. Content and rendering

**Sanitization** : a strict whitelist of elements and attributes, applied before storage and verified before display. Tracking pixels neutralized, scripts, frames and forms removed.

**Reader mode** : main content extracted by a readability-style implementation, in the background, enabled per feed, with a local cache, `robots.txt` honoured, and a per-feed configurable DOM exclusion selector.

**Isolated web view** : no script execution, no third-party cookies, for the cases where an article does not extract correctly.

**Images** : lazy loading, disableable per feed, bounded local cache, Low Data Mode honoured. With no server, no image proxy is possible : the trade-off is lazy loading rather than hiding the IP address.

**Media** : playback of audio and video enclosures, podcast feeds with playback position, background playback and Control Center commands.

**Typography** : control over typeface, size, leading and column width, light, dark and sepia themes.

---

## 11. Indexing and search

### Two indexes

| Index | Scope | Technology | Target volume |
| ----- | ----- | ---------- | ------------- |
| stream | every local article | SQLite FTS5, external content | up to 125,000 |
| library | retained articles | Core Spotlight | a few thousand |

Core Spotlight cannot serve as the primary index : `contentDescription` is capped at around three hundred characters, and the recommendation is to stay within a few thousand items per application, beyond which search performance degrades severely. It suits the library perfectly, with two immediate benefits : retained articles show up in system Spotlight, and natural-language semantic search comes from the system.

### Lexical index of the stream

A contentless FTS5 virtual table, weighting title, standfirst, body and author, kept in step by triggers on the articles and their bodies. Contentless rather than external content : it holds an index and not a second copy of the articles, which is the point either way, and a row can be removed on its identifier alone. External content demands the exact original text back on every delete, and a cascade that has already removed the body has nothing to give back, which is how a full-text index quietly corrupts itself.

The `unicode61` tokenizer with diacritics removed, wrapped in `porter`. The stemmer is English, the only one SQLite ships, and it is close enough on French suffixes to be worth having ; a per-language index is what doing better would take. Language detection at ingestion, stored on the article.

A full rebuild is possible at any time, on the order of a minute over the target corpus.

### Library index

Items handed to Core Spotlight with title, excerpt, author, date, tags and thumbnail. `CSIndexExtensionRequestHandler` is implemented so Spotlight schedules reindexing itself under favourable conditions, device asleep or idle, outside the application lifecycle.

The Spotlight index is local and private, and is never shared between the devices of one account. Every device indexes on its own behalf.

### Semantic search

Over the library only, through Core Spotlight semantic search, falling back on vectors computed by the application and cosine similarity, which needs no particular index structure at this scale.

The stream is not vectorized. Grouping the reprints of one wire story was implemented that way, measured, and abandoned : the system's sentence embeddings scored two unrelated French articles at 0.93 and two about the same event at 0.92. The digest groups on shared vocabulary instead, weighted by rarity, which separates them cleanly and needs no model at all. `docs/technical/digest.md` carries the measurement.

### Targets

| Operation | Target |
| --------- | ------ |
| lexical query over 125,000 articles | under 100 ms |
| semantic search over the library | under 300 ms |
| full FTS5 index rebuild | under 2 min |
| indexing one article at ingestion | under 10 ms |

---

## 12. Query language

An explicit grammar, parsed into a tree, never built by concatenation.

```
tag:veille/ios (title:"vision pro" OR title:visionos) -site:medium.com after:2026-01 is:unread
```

| Category | Operators |
| -------- | --------- |
| fields | `title:`, `text:`, `author:`, `feed:`, `site:`, `tag:`, `lang:` |
| states | `is:unread`, `is:read`, `is:starred`, `is:library`, `has:media`, `has:fulltext` |
| time | `after:`, `before:`, `age:<7d` |
| logic | `AND`, `OR`, `NOT`, nested parentheses, quoted phrases, `-` prefix for exclusion |

Input compatibility with the FreshRSS syntax, `intitle:`, `intext:`, `author:`, `date:`, silently translated at parse time so migrating users are not thrown off.

Input assistance : completion of feed and tag names, a live result count, and explicit flagging of expensive expressions.

---

## 13. Organization and automation

### Promotion to the library

An article enters the library by being starred, tagged, annotated, or by a rule action. At that moment its content is frozen and copied, which is what guarantees it survives the purge of the stream and its disappearance from the source.

### Rules

A condition expressed in the query language, with composable actions :

- add or remove a tag ;
- mark read or unread ;
- promote to the library ;
- hide ;
- notify locally.

Two mandatory properties :

1. **replay over history**, with a preview of the number of affected articles before execution ;
2. **simulation** with no side effect, with a sample of the matches.

Explicit evaluation order, individual enabling, and a consultable local log of triggers.

### Retention

Stream purge by age and by volume, with a configurable global cap expressed in days and in megabytes. What belongs to the library is never purged. This is the mechanism that bounds disk usage.

---

## 14. On-device enrichment

Optional, switchable off, never required for nominal operation.

Classification, automatic tagging and summaries by the system model, through the Foundation Models framework.

Constraints built in from the start :

- a fixed 4,096-token context window on the on-device model, input and output together, driven by `contextSize` and `tokenCount(for:)` rather than by a hard-coded value ;
- per-device availability, since the user can turn Apple Intelligence off : the model is treated as a feature flag, with a no-LLM path always present and tested ;
- a long article does not fit in the window, so summarizing proceeds by chunking then aggregation.

In practice, classification and tagging fit the budget in a single pass, and summarizing a long article takes two.

Anything produced automatically is flagged as such in the interface and in exports.

**What the model writes is written in the reader's language**, not in the language of the articles. Someone watching a subject follows the press that covers it, whatever it is written in, and a digest half in one language and half in another is one the reader has to translate themselves. The articles keep their own language ; only the headline and the line above them are written. A language the model does not support falls back to the articles' own, since a model asked for a language it does not speak answers in a mixture of the two.

No sending to a remote service by default. If the user configures an external provider, consent is asked per feed and outgoing calls are logged locally.

### Vectors and multiple devices

Library vectors are synchronized, not recomputed. The system's own sentence embeddings produce them, on the device, with no download and no dependency on Apple Intelligence ; the dimension is the model's, around five hundred. Quantized to 8-bit integers, scaled by the vector's own largest component, that is about five hundred bytes each and a megabyte for the whole library. The scale is not stored : reading a vector normalizes it again, and a cosine does not care how long either vector was.

**Compatibility rule, mandatory.** A vector is only comparable to those produced by the same model and the same revision, and system models evolve with the operating system. The model identifier and revision are stored with every vector. On a mismatch the received vector is ignored and recomputed locally, never mixed, and the most up-to-date device republishes its version.

---

## 15. Background processing

Two workloads of different natures. Lexical indexing is negligible, on the order of a second to a minute for the whole corpus, and happens inline at ingestion. Vectorization is the only genuinely expensive work, and that is why it is limited to the library : two thousand five hundred items at a hundred milliseconds is about four minutes, feasible on an iPhone while charging.

| API | Use |
| --- | --- |
| `BGAppRefreshTask` | opportunistic feed refresh, never critical, about thirty seconds |
| `BGProcessingTask` | vectorization, deferred full-text extraction, purge, compaction, with `requiresExternalPower` |
| `BGContinuedProcessingTask` | first import and full reindex, triggered by the user |
| `NSBackgroundActivityScheduler` | the macOS equivalent |

`BGContinuedProcessingTask` inverts the usual model : the task starts on an explicit action, a button press or a gesture, and the system then commits to letting it finish, showing its own progress interface which the user can follow and cancel. A dedicated entitlement allows background GPU access, subject to checking `BGTaskScheduler.supportedResources`.

This API is not perfectly reliable in practice yet. Every long task is therefore written to be **resumable** : idempotent batches, and automatic resumption at the next launch if the task did not finish.

The resume point is the data itself, not a checkpoint beside it. What is left to do is a question the store already answers : the feeds never fetched, the kept articles with no current vector. A checkpoint could only ever disagree with them, and a checkpoint that disagrees is worse than none, because it is believed.

Background refresh is opportunistic by nature, the system alone deciding when according to activity, battery and expected consumption, and the user being able to turn it off. Permanent freshness is therefore not promised, and the interface never presents an unread count as though it were real time.

**Mandatory configuration** : every identifier declared in the Info.plist under `BGTaskSchedulerPermittedIdentifiers`, failing which `submit(_:)` throws `notPermitted`. The Background Modes capability including background processing.

---

## 16. Interface

### The digest, which is the main screen

Not a list of articles : a list of **stories**, each one several articles from several rooms about one thing. An aggregator shows what arrived and leaves the reader to work out what matters ; this shows what is happening, how many rooms are saying it, and whether it is still moving.

- **Happening now** : the stories with at least three articles from two rooms in the last six hours. Ten articles from one room is not an event.
- **The subjects**, as pills that scroll : the front page first, then the subjects the model found across the stories, most covered first. **Amended** : this section asked for a day, week and month selector. A period is a question about the calendar, and nobody watching a subject asks it. The front page looks back three days, which is a story still worth a headline, and everything older stays reachable through unread, the library and search.
- A story is under exactly one subject, or under none, in which case it is still on the front page and simply on no pill. Without a model there are no subjects and no pills, and the front page is entire ; a model that answers nothing leaves the subjects already on the page alone, rather than blanking a good page over a transient.
- **The tail** : what grouped with nothing, still there as the ordinary articles it is.

The first story on the page runs its picture across the column, above a larger headline ; the others keep theirs to a square at the side. A page where every story is the same size is a list, and a list makes the reader do the ranking the digest exists to do.

Each story carries its name, one line saying what happened, the marks of the rooms talking about it rather than a count of them, the number of articles, the shape of their arrival and how long ago the last one came. Opening a story lists its articles ; opening an article reads it. Not a card : a rule, a headline, a line and the facts underneath.

The model names and summarizes ; without one, a story takes the title and standfirst of its most central article, and the page says which of the two it is. `docs/technical/digest.md` records how stories are grouped, and why it is not by the vectors of section 11.

### Common structure

**Amended.** This section asked for three levels, sidebar, list and article, shown as three columns on iPad and Mac. What is built shows one column at a time on every platform, under the system tab bar : the digest, unread, the library, sources, and search. Two columns of chrome around an article are two columns of not reading, and the sections a sidebar was to hold are the sections the tab bar holds. Each section keeps its own navigation stack.

On macOS those same sections become a sidebar, drawn by the system for an adaptable tab view, since a Mac window keeps its sections at the side.

Views the sidebar was also to list, today, starred, tags, saved queries and individual feeds, are reached from the sources section rather than from a permanent column.

The digest, a story and an article are set as a page rather than as a control panel : one column held to a readable measure, serif headlines, hairline rules, no cards and no boxes. Liquid Glass appears only in the navigation layer, which is the system's own bar, and never in the content. `docs/technical/interface.md` records the design and what was rejected.

### List

Adjustable density, a one- to three-line excerpt, an optional thumbnail, a feed indicator, optional mark-as-read on scroll, configurable swipe gestures, multiple selection and batch actions.

The picture an article carries is taken from the feed, or failing that from the first picture in the body, and only its address is stored : the file stays the publisher's and is asked for when a screen shows it. `docs/technical/ingestion.md` records the order, `docs/technical/interface.md` how the page uses it.

### Article

Reader mode by default when extraction succeeded, a switch to the feed content or the web view, keyboard navigation on Mac and iPad, a constant action bar : read, star, tag, share, open in the browser.

### Search

A single field accepting the query language, live results, a switch between stream and library, and saving a query straight from the field.

### macOS

A window whose sections sit in a sidebar, complete keyboard shortcuts, a menu bar, customizable toolbar items, multiple windows, and inbound and outbound drag and drop.

### Widgets and extensions

Unread, library and saved-query widgets. A Share extension for subscribing and promoting. Controls for Control Center and the Lock Screen.

### First launch

An OPML import or an import from an existing service offered right away, an optional starter set of feeds, a one-sentence explanation of the stream and library split, and no account creation.

---

## 17. Accessibility and internationalization

- Full VoiceOver support, including reading order inside articles and gesture labels.
- Dynamic Type on every view, with no truncation, tested up to the accessibility sizes.
- Increased contrast, reduced motion, reduced transparency.
- Complete keyboard navigation on iPad and Mac, with a shortcut list.
- Initial localization in French and English, strings externalized from M0 on, right-to-left support planned for in the layouts.
- Date, number and collation formats following the locale.

---

## 18. Automation and agents

**App Intents** on every platform : subscribe to a URL, mark a view as read, run a saved query, promote an article, get the unread count. Exposed to Shortcuts, Spotlight and Siri.

**A local MCP server** on macOS, over standard input and output transport, for desktop agents. Read tools by default : `search`, `get_article`, `list_feeds`, `list_unread`, `run_saved_query`, `stats`. Write tools stay disabled until the user explicitly enables them, and every action is logged locally.

This entry point is local to the machine ; it is neither remote nor available with the machine switched off.

**Local outgoing feeds** : any view, tag or saved query can be exported as an Atom or JSON Feed file, to feed other tools.

---

## 19. Import, export, migration

**OPML import**, including the common proprietary attributes, preserving the folder tree and tolerating malformed files.

**Import from an existing service** : FreshRSS and Miniflux through their API, Feedbin and Feedly through theirs. Subscriptions, folders, labels, stars and read states are retrieved, after which Flong runs on its own. No permanent synchronization is kept with the origin service.

**Query translation** from FreshRSS to the Flong language, with an explicit report of the expressions that could not be translated rather than a silent approximate conversion.

**Export** : OPML for subscriptions, JSON for everything, tags, rules, queries, library and annotations included. A complete export must be able to rebuild the state of the application on a fresh install.

The initial import runs in a resumable task with system progress.

---

## 20. Security and privacy

- No data leaves the device, apart from the private CloudKit database and the requests to the feeds themselves.
- No telemetry, no tracker, no third-party service active by default.
- Secrets in the keychain exclusively.
- The local database under data protection, "after first unlock" class.
- Whitelist HTML sanitization, a web view with no script and no third-party cookie.
- Lazy and disableable image loading, tracking pixels neutralized.
- Optional application lock by Face ID, Touch ID or password.
- No logging of article content or of a secret URL, including on a crash.
- A privacy policy and an App Store privacy nutrition label consistent with the above : no collection.

---

## 21. Performance and budgets

| Quantity | Target |
| -------- | ------ |
| followed feeds | 1,000 |
| articles kept locally | 125,000, around 500 MB |
| library items | 2,500 |
| CloudKit records over three years | around 3,000 |
| cold launch to a usable list | under 500 ms |
| refresh of 300 feeds on a decent network | under 60 s |
| memory footprint while reading | under 150 MB |
| cellular consumption per day, default settings | under 10 MB |

Automatic purge triggered when the volume cap is exceeded, with the user informed, and never deleting a library item.

---

## 22. Quality and testing

- Unit tests on the parser, with a corpus of real malformed feeds built from M0 on.
- Tests on the query language parser, hostile input included.
- Performance tests on a synthetic corpus of 125,000 articles, run in continuous integration, with blocking thresholds matching the targets of section 11.
- Synchronization tests simulating several devices, including concurrent read-state merges and recovery after rate limiting.
- A complete install walkthrough test on an iPhone alone, with no other device on the account. Blocking.
- A test of the no-Apple-Intelligence path on an ineligible device. Blocking.
- Automated verification that no secret and no private URL appears in the logs.
- No automatic crash reporting without explicit consent.

---

## 23. Distribution and license

Distribution through the App Store on the three platforms. The application is free.

| Component | License |
| --------- | ------- |
| the application, in its entirety | MPL 2.0 |
| extracted, reusable libraries : parser and query language | Apache 2.0 |

MPL 2.0 requires any modification of a covered file to be republished under the same license, which guarantees improvements come back, while staying compatible with App Store distribution. The GPL family is ruled out : its terms are incompatible with the store's, which has already led to applications being pulled.

This split has to be frozen before the first external contribution is accepted, after which any change would need every contributor's agreement.

Flong is not affiliated with any third-party service. Service names cited in the application are there for interoperability.

---

## 24. Milestones

| Milestone | Contents | Exit criterion |
| --------- | -------- | -------------- |
| M0 | collection, parsing, storage, reading | 300 feeds followed for a week with no intervention |
| M1 | FTS5 index, query language, search | the targets of section 11 met over 125,000 articles |
| M2 | library, promotion, Core Spotlight | retained articles found in system Spotlight |
| M3 | `CKSyncEngine` synchronization | a second device added with no bulk transfer, and the complete walkthrough validated on an iPhone alone |
| M4 | background tasks, vectors, vector sharing | a complete import resumed and finished after backgrounding |
| M5 | tags, rules, replay, saved queries | a rule replayed over the whole local corpus in under a minute |
| M6 | enrichment, App Intents, widgets, local MCP | the no-LLM path verified on an ineligible device |
| M7 | import and export, accessibility, localization | a complete export reimported identically on a fresh install |

---

## 25. Risks

| Risk | Scope | Mitigation |
| ---- | ----- | ---------- |
| undocumented CloudKit caps | blocking | a three-thousand-record budget, no bulk transfer, both forms of rate limiting handled |
| background tasks never triggered | functional | foreground refresh as the primary mechanism, background tasks treated as a bonus |
| `BGContinuedProcessingTask` unreliable | functional | resumable tasks in idempotent batches, a persisted resume point |
| articles missed by a switched-off device | functional | thirty-day catch-up headers |
| Core Spotlight caps | design | use restricted to the library, sized under the caps by construction |
| model divergence between devices | data | identifier and revision stored, local recomputation rather than mixing |
| drift towards a mandatory Mac | product | no macOS-exclusive feature allowed, blocking install test on an iPhone alone |
| traffic multiplied by device count | externality | systematic HTTP conditionality, pseudo-random stagger |
| third-party dependency for newsletters | product | flagged in the interface, never mandatory |
| iCloud quota full | user | `quotaExceeded` detected, an explicit message, a purge offered |
