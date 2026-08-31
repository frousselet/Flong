# Flong, product and technical specification

Version 1.0, 29 August 2026.

This page is the reference every other document defers to. `CLAUDE.md` holds the working conventions, `README.md` the public presentation, and `docs/technical/` the detail of one subject at a time. When any of them disagrees with this page, this page wins.

---

## 1. Summary

Flong is a feed reader for iOS, iPadOS and macOS. There is no server, no account to create, no hosting. The data lives on the user's devices and propagates through their private CloudKit database.

The product rests on three commitments.

**One article, and what the reader said about it.** There is a single notion of an article and no second copy of anything. What the reader says about one - starred, written on, filed in a collection - is a mark carried on the article itself, and it is what makes the article theirs : a mark is synchronized, is never purged, and is the whole of what distinguishes a kept article from one that merely arrived.

**Amended.** This section, and the whole document with it, used to describe a clean split between a disposable stream and a frozen library. The split was dissolved deliberately, and section 4 sets out what each half of it was for and what became of it : once the stream is retained without limit and synchronized whole, a second store holding a frozen copy of a subset of it has nothing left to protect.

**Search that is genuinely indexed.** A local full-text index over the whole corpus, a query language with operators, and semantic search over what the reader marked.

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

**Reading stream** : the set of articles present locally. It began as a local cache, bounded in age and volume and never synchronized ; it is now retained without limit and synchronized whole, which is what dissolved the library below.

**Mark** : what the reader said about an article, carried on the article itself : starred or not, the note if there is one, and the collections it was filed into. A mark is synchronized, and an article that carries one is never purged.

**Collection** : a set of articles the reader looks at as one thing, of one of three natures - predefined, made article by article, or described by a query. See section 13.

**Library** : *removed*. It was a second table holding a frozen copy of what the reader chose to keep, and every reason it existed for went away one at a time :

- it survived the purge of the stream : nothing is purged now, unless the reader asks, and a marked article is spared even then ;
- it survived the article vanishing from the web : the stream keeps the text and travels with it, so every device has it ;
- it survived a device being set up fresh : the stream travels whole, so it arrives with everything else ;
- it froze the version read, so a later edit could not reach it : the one guarantee that genuinely went, and not worth a second store on its own.

What it really held, once the frozen text stopped being wanted, was the reader's own marks. Those moved onto the article, which is where they had always belonged.

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
| `Extractor` | full-text extraction, reader mode. `docs/technical/extraction.md` |
| `Store` | SQLite through GRDB, migrations, purge |
| `Indexer` | FTS5 for every article, Core Spotlight for the marked ones |
| `Search` | The query language, and its compilation to SQL |
| `Enricher` | vectors, classification, rule execution |
| `Sync` | `CKSyncEngine` on the private database |
| `Notify` | Local notifications : what is worth saying, and the rules for saying it |
| `Automation` | App Intents, widgets, local MCP server on macOS |
| `Import` | OPML and service imports, exports |

SQLite is driven directly through GRDB. SwiftData is ruled out : the volume is large, the concurrency needs fine control, and FTS5 virtual tables need direct access.

GRDB is the only external dependency, and it stays that way. A package is added only where writing the equivalent ourselves would be unreasonable ; everything else comes from the system frameworks.

---

## 6. Local data model

| Table | Contents |
| ----- | -------- |
| `feed` | canonical URL, title, folder, conditionality metadata (`etag`, `last_modified`), health, observed periodicity, local settings |
| `entry` | article, stable identifier, metadata, read state, reception date, and the reader's own marks : starred, annotation, vector with its model identifier and revision |
| `entry_body` | sanitized body, extracted body, normalized plain text |
| `entry_fts` | FTS5 virtual table, contentless, kept in step by triggers |
| `pending_mark` | a mark that arrived from another device before the article it is about |
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
| marks | 1,000 to 2,500 | starred, annotation, collections, vector |
| read-state blocks | a few dozen | compressed sets of fingerprints, one per month |
| catch-up headers | a few hundred, sliding | metadata only |
| **target total** | **around 3,000** | |

For comparison, one record per article would mean more than a hundred thousand records over the same period.

### Read-state compaction

One record per month, holding the compressed set of short fingerprints of the articles read in it.

Per month, and not per feed and per month : a reader following three hundred feeds would otherwise write three hundred records a month, which the budget above exists to prevent. A month of a heavy reader is a few tens of kilobytes, well inside one record.

A fingerprint is eight bytes of a digest of the feed address and the article's own identity, which two devices work out to the same value without ever having spoken. Local identifiers cannot travel ; these can.

Starred articles are not in these blocks. A star travels as a mark of its own, which is a record with a real deletion. A set of fingerprints only grows, and unstarring would have nowhere to go in it.

Merging is a union, so the operation is commutative and idempotent. There is no conflict resolution logic to write, which removes the main source of bugs in multi-device synchronization. It follows that reading is one way : marking an article unread is a local decision and does not travel. That is the price of having no conflict resolution at all, and it is worth paying.

### Marks

One record per marked article, named after the pair of feed address and article identity, so two devices marking the same article write one record between them.

**Not compacted into a block per month**, which is the shape read states take and the shape this was first written as. Reading happens once and never unhappens, so a union merge is right for it and is commutative : two devices writing the same month cannot lose each other's work. A mark is not like that. A star comes off, a note is deleted, an article leaves a collection, and the `no` has to travel as surely as the `yes`. In a block that means the last device to write a month wins the whole month, and a star made on one device while another was offline is silently rubbed out. One record per article is the only shape in which the `no` travels and nothing is clobbered, and it costs exactly what the library items it replaces cost : the reader marks a few thousand articles in years, not a hundred thousand.

An article unmarked entirely has nothing left to say, and its record is deleted. The deletion is what carries the `no`.

**A mark may arrive before its article.** The whole stream travels, so the article is on its way, but CloudKit hands its batches over in whatever order it likes. A mark whose article is not here is held in `pending_mark` and written the moment the article turns up, whether from iCloud or from the feed itself. Dropping it would lose a star for good, since nothing re-sends a record that was already delivered.

### Stream blocks

**Amended.** This began as catch-up headers : identifiers and titles only, over a sliding thirty-day window, so that a device switched off for a week learned what had already dropped out of its feeds. The reader asked for the whole stream instead, kept for good on every device, and retention was made unlimited to match. The window is gone and the bodies travel.

The shape did not change, and that is what makes it possible at all : one record per feed, per day, cut into as many chunks as its bytes need, carrying every article of that day with its text compressed. Never one record per article. A day that has passed never changes again, so a block is written once and not rewritten, which is what change throughput punishes.

**Records carry the near end of the history only.** The record count is feeds multiplied by the days they published on. It is bounded for a reader following a few dozen feeds and it is not bounded for one following three hundred over several years, where it reaches six figures and meets the same rate limiting one record per article would. Unlimited retention and a per-record store are not reconcilable by any choice of record shape : the data grows without bound and CloudKit charges by the record. What records buy is speed, a push arriving in seconds, so they carry the recent days and the archive carries the rest.

### Stream archives

The bulk of the stream travels as files in the iCloud Documents container, where the charge is for bytes and the reader has said the bytes are theirs to spend.

**One writer per file.** File synchronization goes wrong when two devices write one file and somebody has to resolve a conflict nobody can resolve correctly. Each device writes only inside a folder of its own, named by an identifier it keeps locally and never shares, and reads everybody else's. No file is written twice, so there is no conflict to have : it is an append-only log per device, which is the shape that merges by doing nothing.

One file per device and per day, compressed, holding every feed's articles for that day with their text. Three devices over three years is around three thousand files, each sealed by the day ending and never touched again ; the day in progress is the only one rewritten.

Which archives a device has already read is kept locally, in `archive_ingest`. A ledger that travelled would have every device skip what only one of them had read.

**What it costs in return.** A file arrives when it arrives : iCloud Documents downloads on demand and has no push behind it, where a record pushed through `CKSyncEngine` arrives in seconds. That is why both exist, and why read states, which have to be prompt, stay records.

### What never transits

Indexes, vectors of articles that were not retained, secrets, any log. Nor the ledger of which archives a device has read, which is about the device and not about the reading.

### What it takes to work

The archives need the `com.apple.developer.ubiquity-container-identifiers` entitlement and `CloudDocuments` among the iCloud services, both of which the target carries, against the same container as CloudKit. Where an entitlement is absent, or an iCloud account is, the container is absent with it : everything to do with archives then does nothing at all rather than failing, and the reader loses the sharing of the stream and nothing else.

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

**Amended.** Cookie sessions are in scope. The reason this section gave for excluding them was a good one and still holds : a site's login form is not an interface anybody promised to keep, and a session breaks when the site decides it does, with no warning and no error a program can read. What changed is the weighing, not the facts. A reader who pays for a newspaper and cannot read it in the reader they chose is a reader the application has failed, and a session that has to be renewed by hand now and then is a smaller failure than that.

The cost is made legible rather than hidden : a session records when it was signed in and when it last worked, and a site that has stopped recognizing the reader says so instead of quietly serving teasers.

**Still out of scope** : form authentication, OAuth, and working around a paywall for something the reader has not paid for. Flong never holds a site's password, never fills in a login form and never automates a sign-in : the reader signs in on the site's own page, in a web view, and what is kept is the session that page left. There is nothing to be trusted with because nothing is given.

`docs/technical/credentials.md` records how a session is scoped to its own site and no other.

**Secret storage** : the keychain exclusively, with the appropriate protection class, propagated between devices by iCloud Keychain. Never in the database, never in CloudKit, never in a log. `docs/technical/credentials.md` records how a secret address is identified without being written down.

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
| full text | every local article | SQLite FTS5, contentless | hundreds of thousands |
| system | the marked articles | Core Spotlight | a few thousand |

Core Spotlight cannot serve as the primary index : `contentDescription` is capped at around three hundred characters, and the recommendation is to stay within a few thousand items per application, beyond which search performance degrades severely. It suits the marked articles perfectly, with two immediate benefits : what the reader kept shows up in system Spotlight, and natural-language semantic search comes from the system.

### Lexical index

A contentless FTS5 virtual table, weighting title, standfirst, body and author, kept in step by triggers on the articles and their bodies. Contentless rather than external content : it holds an index and not a second copy of the articles, which is the point either way, and a row can be removed on its identifier alone. External content demands the exact original text back on every delete, and a cascade that has already removed the body has nothing to give back, which is how a full-text index quietly corrupts itself.

The `unicode61` tokenizer with diacritics removed, wrapped in `porter`. The stemmer is English, the only one SQLite ships, and it is close enough on French suffixes to be worth having ; a per-language index is what doing better would take. Language detection at ingestion, stored on the article.

A full rebuild is possible at any time, on the order of a minute over the target corpus.

### System index

The marked articles are handed to Core Spotlight with title, excerpt, author, date, tags and thumbnail. An article is marked when the reader did something to it : starred it, wrote on it, or filed it in a collection. Everything else is a cache nobody chose, and a system-wide index of a cache is an index of things nobody asked for. `CSIndexExtensionRequestHandler` is implemented so Spotlight schedules reindexing itself under favourable conditions, device asleep or idle, outside the application lifecycle.

The Spotlight index is local and private, and is never shared between the devices of one account. Every device indexes on its own behalf.

### Semantic search

Over the marked articles only, through Core Spotlight semantic search, falling back on vectors computed by the application and cosine similarity, which needs no particular index structure at this scale.

The stream is not vectorized. Grouping the reprints of one wire story was implemented that way, measured, and abandoned : the system's sentence embeddings scored two unrelated French articles at 0.93 and two about the same event at 0.92. The digest groups on shared vocabulary instead, weighted by rarity, which separates them cleanly and needs no model at all. `docs/technical/digest.md` carries the measurement.

### Targets

| Operation | Target |
| --------- | ------ |
| lexical query over 125,000 articles | under 100 ms |
| semantic search over the marked articles | under 300 ms |
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
| states | `is:unread`, `is:read`, `is:starred`, `is:collected`, `is:annotated`, `has:media`, `has:fulltext` |
| time | `after:`, `before:`, `age:<7d` |
| logic | `AND`, `OR`, `NOT`, nested parentheses, quoted phrases, `-` prefix for exclusion |

Input compatibility with the FreshRSS syntax, `intitle:`, `intext:`, `author:`, `date:`, silently translated at parse time so migrating users are not thrown off.

Input assistance : completion of feed and tag names, a live result count, and explicit flagging of expensive expressions.

---

## 13. Organization and automation

### Marking an article

**Amended.** This section described promotion to the library : starring, tagging or annotating an article froze a copy of it in a second table, which is what guaranteed it survived the purge and the article's disappearance from the source.

There is no second copy any more, and there is no library. Starring, writing on or filing an article writes a mark on the article itself. The mark is what is synchronized, and an article carrying one is never purged, whatever the retention policy says. Section 4 lists the guarantees the copy used to give and what became of each ; the short of it is this : retention is unlimited and the whole stream travels between devices, so the article does not need protecting from the purge, and the marks are on it rather than beside it, so nothing can drift out of step with anything.

What is genuinely lost is freezing the version read : a publisher's later edit now reaches the article. That was the one thing the copy still bought, and it was not worth a second store.

### Rules

A condition expressed in the query language, with composable actions :

- add or remove a tag ;
- mark read or unread ;
- star, or write on ;
- hide ;
- notify locally.

Two mandatory properties :

1. **replay over history**, with a preview of the number of affected articles before execution ;
2. **simulation** with no side effect, with a sample of the matches.

Explicit evaluation order, individual enabling, and a consultable local log of triggers.

### Collections

Three natures, and what travels is different for each. That is not an implementation detail : it is the whole of what tells them apart, and getting it wrong is how a budget of three thousand records becomes a hundred thousand.

| Nature | What it is | What travels |
| ------ | ---------- | ------------ |
| **Built-in** | A question every reader's articles answer about themselves : favourites, notes | The state of one article, yes or no, on that article's own record |
| **Made** | Filled article by article | The pair, this article in that collection, as a field on the article's record |
| **Dynamic** | Described rather than filled | The description, and never what answers it |

Nothing new was needed in the store for any of it. A built-in one is a column ; a made one is a tag under a `collection/` root bound through `tag_binding`, which section 4 already described ; a dynamic one is the `saved_query` of section 5 holding a name and an expression of the query language of section 12. All three had been in the schema since v1.

**The dynamic one is the reason to have three.** It costs one small record whether it holds nothing or ten thousand articles, because a description is a description. It also has no membership to keep in step : it answers itself, at the moment it is asked, from whatever the reader has.

**Made, never unmade.** A name arriving from another device is created ; a name absent from what arrived is not deleted. Deleting is therefore local until every device has been told by other means, which is the price of not carrying a tombstone for every name ever used. Membership is the other way round : what arrives about one article is the whole truth about it, so a collection missing from its list is one it was taken out of.

### Notifications

Everything Flong may interrupt the reader for is a switch in the reader's own menu, and every switch starts off.

**Local, and only local.** There is no server, so there is nobody to send a notification : each device writes what it shows, about something it worked out for itself. Two devices may say the same thing at different moments, or one of them not at all, and that is correct rather than a drift to reconcile. The silent push of section 7 is `CKSyncEngine` telling this device that another one changed something, and nothing that arrives that way is ever shown.

**Permission is asked when the reader asks.** Turning a switch on is what prompts the system. A prompt at first launch is a prompt about something the reader has not seen yet, which is how an application is refused permanently for a feature that would have been welcome later. A refusal is final until the reader goes to the system settings, so the switch goes back where it was and the screen says where the answer lives.

What the reader wants travels between their devices, through the key-value store of section 7 ; whether a given device may interrupt them is the system's answer on that device and never travels. The two are different questions and it is right that they disagree.

**The first of them : a new story.** A story is several articles, from several newsrooms, about one thing, and one opening is the moment the press starts covering something. A cluster of one is not a story, so this is not a notice per article. Nothing that was already open when the switch was turned on is announced.

**Nothing interrupts a reader who is looking at the page it would be about.** A story that opens appears on the front page, so a reader with Flong open has already seen it. The watermark moves anyway : what it records is that the story reached them, not that a notification was posted.

`docs/technical/notifications.md` carries the rules and what each is for.

### Retention

**Amended : nothing is thrown away on its own.** Both bounds, age and volume, are optional and both are absent. The reader keeps every article that has ever arrived, on every device. The purge still exists and is still correct ; it is asked for, from the sources page, rather than run on a schedule.

Purge by age and by volume, with a configurable global cap expressed in days and in megabytes. **An article the reader marked is never purged, however it was marked.** Starring is not the only way to say something about an article : a note and a filing say it just as plainly, and a purge sparing only the stars would throw away the article somebody wrote three paragraphs on.

---

## 14. On-device enrichment

Optional, switchable off, never required for nominal operation.

Classification, automatic tagging and summaries by the system model, through the Foundation Models framework.

Constraints built in from the start :

- a fixed 4,096-token context window on the on-device model, input and output together, driven by `contextSize` and `tokenCount(for:)` rather than by a hard-coded value ;
- per-device availability, since the user can turn Apple Intelligence off : the model is treated as a feature flag, with a no-LLM path always present and tested ;
- a long article does not fit in the window, so summarizing proceeds by chunking then aggregation.

In practice, classification and tagging fit the budget in a single pass, and summarizing a long article takes two.

**The framework gives the on-device model and nothing else.** There is no cloud, server or remote option in its interface : Apple's own features route to Private Cloud Compute, an application's own prompts cannot. That happens to agree with section 3, which would not have it either.

What the framework does offer is used, and set in one place : the permissive content-transformation guardrails, since what is asked for is a transformation of articles the reader already receives and the default set refuses a great deal of ordinary news ; greedy sampling, so a rebuild does not rewrite a page the reader was reading ; a cap on the answer ; and the locale check, which decides what language to ask for rather than whether to ask.

**Giving up on the model is a pause, never a latch.** Three failures of the model itself, as opposed to three stories it declined to write about, are enough to stop asking for a while. They used to be enough to stop asking for the life of the process, since nothing cleared the count but a success and no success is possible while every caller checks availability first : on a Mac that is days. A rate limit does not count towards it at all, a backgrounded application's sessions being rate-limited hard enough that three of those silenced the model for a whole night's work. The tuned `contentTagging` model was measured against the general one for filing and is worse at it, which `docs/technical/digest.md` records.

**A headline is written to the rules a desk would apply.** It says in a few words what the group contains and makes somebody want to read it, in that order of importance : every word carries information, no jargon and no abstraction, a named actor and a verb of action before a general idea, the words a reader would look for first since it is read in a list and often cut short, and clarity before cleverness, wordplay needing a readership and an editorial line that a model writing for one stranger does not have. Twelve words is the ceiling and it is enforced, not merely asked for. Above all it never promises more than the articles say : the gap between a headline and what it delivers is what destroys the credit of a publication, and a page nobody signed has less of that credit to spend. The line beneath states the angle and answers what the headline had no room for, and is never the headline again in other words. `docs/technical/digest.md` sets out how each of those is checked.

Anything produced automatically is flagged as such in the interface and in exports.

**What the model writes is written in the reader's language**, not in the language of the articles. Someone watching a subject follows the press that covers it, whatever it is written in, and a digest half in one language and half in another is one the reader has to translate themselves. The articles keep their own language ; only the headline and the line above them are written. A language the model does not support falls back to the articles' own, since a model asked for a language it does not speak answers in a mixture of the two.

No sending to a remote service by default. If the user configures an external provider, consent is asked per feed and outgoing calls are logged locally.

### Vectors and multiple devices

Vectors are synchronized, not recomputed, and only the marked articles have one. The system's own sentence embeddings produce them, on the device, with no download and no dependency on Apple Intelligence ; the dimension is the model's, around five hundred. Quantized to 8-bit integers, scaled by the vector's own largest component, that is about five hundred bytes each and a megabyte for all of them together. The scale is not stored : reading a vector normalizes it again, and a cosine does not care how long either vector was.

**Compatibility rule, mandatory.** A vector is only comparable to those produced by the same model and the same revision, and system models evolve with the operating system. The model identifier and revision are stored with every vector. On a mismatch the received vector is ignored and recomputed locally, never mixed, and the most up-to-date device republishes its version.

---

## 15. Background processing

Two workloads of different natures. Lexical indexing is negligible, on the order of a second to a minute for the whole corpus, and happens inline at ingestion. Vectorization is the only genuinely expensive work, and that is why it is limited to the marked articles : two thousand five hundred of them at a hundred milliseconds is about four minutes, feasible on an iPhone while charging.

| API | Use |
| --- | --- |
| `BGAppRefreshTask` | opportunistic feed refresh and grouping, never critical, about twenty-five seconds, spent on the most overdue feeds first |
| `BGProcessingTask` | the full pass, with `requiresExternalPower` and `requiresNetworkConnectivity` |
| `BGContinuedProcessingTask` | first import and full reindex, triggered by the user |
| `NSBackgroundActivityScheduler` | the macOS equivalent |

**The full pass is what a device at rest on the mains does.** Every feed a reader follows, and not only the ones politeness says are due, then the enrichment, the purge, the index and the exchange with iCloud, in that order so everything downstream works on what has just arrived. The opportunistic refresh is what a phone in a pocket gets and is deliberately small. It fetches and groups but never runs the model, a backgrounded application's sessions being rate-limited hard enough that a handful of refusals there silences the model for the rest of the process.

Its shape is read off Photos, whose `photoanalysisd` does the same kind of thing for the same reason : the mains, a six-hour interval, a hundred-minute floor between two runs, up to forty-five minutes of jitter, and one heavy pass at a time. The jitter matters more here than there, a reader's devices otherwise waking together to ask three hundred publishers the same question at the same second, which is what the per-device stagger of section 8 exists to prevent. Photos' `PreventsDeviceSleep` is deliberately not taken : a feed reader holding a Mac awake is one nobody keeps, and what a pass misses tonight it does tomorrow. `docs/technical/background.md` sets out what else was taken and what was left.

`BGContinuedProcessingTask` inverts the usual model : the task starts on an explicit action, a button press or a gesture, and the system then commits to letting it finish, showing its own progress interface which the user can follow and cancel. A dedicated entitlement allows background GPU access, subject to checking `BGTaskScheduler.supportedResources`.

This API is not perfectly reliable in practice yet. Every long task is therefore written to be **resumable** : idempotent batches, and automatic resumption at the next launch if the task did not finish.

The resume point is the data itself, not a checkpoint beside it. What is left to do is a question the store already answers : the feeds never fetched, the kept articles with no current vector. A checkpoint could only ever disagree with them, and a checkpoint that disagrees is worse than none, because it is believed.

Background refresh is opportunistic by nature, the system alone deciding when according to activity, battery and expected consumption, and the user being able to turn it off. Permanent freshness is therefore not promised, and the interface never presents an unread count as though it were real time.

**Mandatory configuration** : every identifier declared in the Info.plist under `BGTaskSchedulerPermittedIdentifiers`, failing which `submit(_:)` throws `notPermitted`. The Background Modes capability including background processing.

---

## 16. Interface

### The digest, which is the main screen

Not a list of articles : a list of **stories**, each one several articles from several rooms about one thing. An aggregator shows what arrived and leaves the reader to work out what matters ; this shows what is happening, how many rooms are saying it, and whether it is still moving.

- **Live stories** : the ones with at least three articles from two rooms in the last six hours. Ten articles from one room is not an event, and a room is a newsroom rather than a feed : a paper with a feed per desk counts once. The heading is set in the colour of the pulsing dot beside it, at the quiet end of its pulse : the dot is the loud thing, the word is what it means, and the pair reads as one mark rather than as two red things competing.
- The same article reaching the reader through two feeds of one newsroom is shown once. It keeps both rows, since each belongs to a feed they follow, and `docs/technical/ingestion.md` records what makes two articles the same one.
- **The subjects**, as pills that scroll : the front page first, then the subjects the model found across the stories, most covered first. **Amended** : this section asked for a day, week and month selector. A period is a question about the calendar, and nobody watching a subject asks it. The front page looks back three days, which is a story still worth a headline, and everything older stays reachable through unread, the collections and search.
- A story is under **several** subjects, or under none, in which case it is still on the front page and simply on no pill. Its subjects are shown above its headline, the way a rubric is set above a piece.
- The subjects have **three natures** : the standard sections every newspaper has, seeded at the first launch so a page reads sensibly on its first day ; the reader's own, theirs to add and to remove ; and the model's own, named for one story. The model files each story under a standard or a reader's subject, with no way out of choosing, and then adds what it found the story is actually about. It is never shown its own answers back, which is what stops a page drifting into near synonyms. The model's own wear its mark wherever they are shown.
- The subjects have **three natures**. The standard sections every newspaper has, seeded at the first launch so a page reads sensibly on its first day ; the reader's own, theirs to add and to remove ; and the model's own, named for one story and marked as its own wherever they are shown. Filing is two passes : the model files each story under a standard or a reader's subject, with no way out of choosing, and then names what the story is actually about. It is never shown its own answers back, which is what stops a page drifting into near synonyms.
- The subjects are a **vocabulary**, written once and kept. A story is filed into it once and keeps what it was given, and the reader may write subjects of their own, which the model files under like any other.
- A long press on a subject says more of this or less of this, on a score from minus three to three that starts at nought. A screen in the reader's menu lists every subject there is, including those no longer on the page, and sets each to down, nothing or up. The score orders the stories before their weight does, and orders the pills themselves. It stays on the device for now : `docs/technical/digest.md` says why it ought not to. Without a model there are no subjects and no pills, and the front page is entire ; a model that answers nothing leaves the subjects already on the page alone, rather than blanking a good page over a transient.
- **The tail** : what grouped with nothing, still there as the ordinary articles it is.

The first story on the page runs its picture across the column, above a larger headline ; the others keep theirs to a square at the side. A page where every story is the same size is a list, and a list makes the reader do the ranking the digest exists to do.

Each story carries its name, one line saying what happened, the marks of the rooms talking about it rather than a count of them, the number of articles, the shape of their arrival and how long ago the last one came. Opening a story lists its articles ; opening an article reads it. Not a card : a rule, a headline, a line and the facts underneath.

The model names and summarizes ; without one, a story takes the title and standfirst of its most central article, and the page says which of the two it is. `docs/technical/digest.md` records how stories are grouped, and why it is not by the vectors of section 11.

### Common structure

**The page keeps itself up to date.** The window follows the store through `DatabaseRegionObservation`, so a change from anywhere reaches it : a background refresh, another device through `CKSyncEngine`, an archive read in. A burst settles before anything is read back, and the article list is left alone while an article is open. A clock every five minutes asks the publishers, which section 8's politeness then decides per feed, since following the store shows what has arrived and nothing in it asks for more. Every automatic trigger goes through one entry point that fetches, groups and reads the page back, so the front page gains stories from a background pass and from a clock tick and not only from a cold launch. A pull on the front page, and on no other, says now rather than soon : it fetches every feed and groups what arrived, and the page is read back once the control has retracted rather than under it. The wire has none, being a list of what has arrived. Asking without the gesture is `Actualiser` in the reader's own menu, which does the same thing and is the only way on a Mac. While a phase is actually running, a line at the head of the front page names it and fills a rule where there is a real count to fill it with, and goes when there is nothing left to say ; `docs/technical/interface.md` sets out why it is in the pinned header and why it answers to no gesture.

**Amended.** This section asked for three levels, sidebar, list and article, shown as three columns on iPad and Mac. What is built shows one column at a time on every platform, under the system tab bar : the digest, the wire, the collections, and search, with the sources reached from the header. Two columns of chrome around an article are two columns of not reading, and the sections a sidebar was to hold are the sections the tab bar holds. Each section keeps its own navigation stack.

On macOS those same sections become a sidebar, drawn by the system for an adaptable tab view, since a Mac window keeps its sections at the side.

Views the sidebar was also to list, today, starred, tags, saved queries and individual feeds, are reached from the sources section rather than from a permanent column.

The digest, a story and an article are set as a page rather than as a control panel : one column held to a readable measure, serif headlines, hairline rules, no cards and no boxes. Liquid Glass appears only in the navigation layer, which is the system's own bar, and never in the content. `docs/technical/interface.md` records the design and what was rejected.

### The wire

**Amended.** This section asked for an unread queue as one of the three levels. The section beside the digest shows **everything, newest first, read or not**, broken by day. A queue is a thing to get to the end of, and a reader watching a subject is not trying to finish anything ; what they want is to see what came in and where they left off. Unread on its own remains a view, in the sources list, for whoever does want it, and the count of unread articles still rides on the section.

### List

Adjustable density, a one- to three-line excerpt, an optional thumbnail, a feed indicator, optional mark-as-read on scroll, configurable swipe gestures, multiple selection and batch actions.

The picture an article carries is taken from the feed, or failing that from the first picture in the body, and only its address is stored : the file stays the publisher's and is asked for when a screen shows it. `docs/technical/ingestion.md` records the order, `docs/technical/interface.md` how the page uses it.

### Article

Reader mode when the reader has chosen it, a switch to the feed content or the web view, the choice remembered and carried between devices by the iCloud key-value store rather than by a CloudKit record, keyboard navigation on Mac and iPad, a constant action bar : read, star, tag, share, open in the browser.

### Search

A single field accepting the query language, live results, and saving a query straight from the field. The switch between stream and library is gone with the library : there is one corpus, and `is:starred`, `is:collected` and `is:annotated` narrow it to what the reader marked.

### macOS

A window whose sections sit in a sidebar, complete keyboard shortcuts, a menu bar, customizable toolbar items, multiple windows, and inbound and outbound drag and drop.

### Widgets and extensions

Unread, collection and saved-query widgets. A Share extension for subscribing and for marking. Controls for Control Center and the Lock Screen.

### First launch

An OPML import or an import from an existing service offered right away, an optional starter set of feeds, a one-sentence explanation of what a mark is and why it never disappears, and no account creation.

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

**Export** : OPML for subscriptions, JSON for everything, tags, rules, queries, collections and annotations included. A complete export must be able to rebuild the state of the application on a fresh install.

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
| marked articles | 2,500 |
| CloudKit records over three years | around 3,000 |
| cold launch to a usable list | under 500 ms |
| refresh of 300 feeds on a decent network | under 60 s |
| memory footprint while reading | under 150 MB |
| cellular consumption per day, default settings | under 10 MB |

Automatic purge triggered when the volume cap is exceeded, with the user informed, and never deleting a marked article.

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
| M2 | marks, collections, Core Spotlight | marked articles found in system Spotlight |
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
| Core Spotlight caps | design | use restricted to the marked articles, sized under the caps by construction |
| model divergence between devices | data | identifier and revision stored, local recomputation rather than mixing |
| drift towards a mandatory Mac | product | no macOS-exclusive feature allowed, blocking install test on an iPhone alone |
| traffic multiplied by device count | externality | systematic HTTP conditionality, pseudo-random stagger |
| third-party dependency for newsletters | product | flagged in the interface, never mandatory |
| iCloud quota full | user | `quotaExceeded` detected, an explicit message, a purge offered |
