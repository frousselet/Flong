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

- Server, account, multi-user.
- Web client, Android client.
- Permanent freshness and notification on publication.
- Receiving e-mail, full read-it-later of the Wallabag kind.
- Remote access by an agent from another machine.

**Amended : a collection may be shared.** This list ruled out social sharing and collaborative annotation, and both are now in scope for collections, through Apple's own sharing rather than through anything of ours. The rest of the line holds and is what makes it possible : there is still no server, no account of ours and no backend service, the data moves between iCloud accounts and none of it reaches us, and section 20 stays true because we still collect nothing. What travels is the excerpt the feed published and never the article. Section 7 says how, and `docs/technical/collaboration.md` says why.

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

**Tag** : a namespaced label, for example `collection/typographie`, applicable to articles. It used to apply to feeds as well, since a folder was a view over a root tag ; there are no folders, so it does not.

**Group of sources** : every feed one publisher serves, keyed by the host they share, which is the same host the digest counts as a room. It is worked out from the addresses and stored nowhere, so there is no group to make, none to keep in step and none left empty. The reader may write a name over one, and that name is the only thing about a group that is kept.

The group is also **who an article is shown to be from**, everywhere it is shown : the name and the favicon on an article row, at the head of an article and in the system index are the publisher's and never the feed's. A favicon is a property of a site, so it is asked for once per group rather than once per desk.

**Folder** : *removed*. A feed carried the path of a folder it sat in, and no screen ever let a reader make one, rename one or take one away : the only folders that existed came out of an imported OPML file, so what the column really held was somebody else's filing, inherited and untendable. Grouping by publisher answers the question a list of two hundred sources actually raises, costs the reader nothing and is right the moment a subscription lands.

**Favourite source** : a publisher the reader singled out. It is not a starred article and it makes none : the star stays a judgement about an article, this is a judgement about who wrote it, and the two fill different squares on the collections page.

**Author** : whoever a feed says signed an article, which is a byline and never a person : there is no row for a writer and there could not be one. The name is the whole of the identity, and two spellings are two authors. **One byline names more than one of them**, no format giving a publisher a second author element they use, so it is cut on the separators that are never anything else and each person gets a row beside the article. What is cleaned off it on the way in is the spelling and never the person : entities, whitespace, the address RSS 2.0 says its own `author` element holds, the word a publisher writes in front of every credit, and a masthead stapled to a name. Capitalization is not, a merge being a judgement rather than a cleaning. The rules are mechanical and deterministic, since the stored byline is what a favourite is named after between devices. See `docs/technical/authors.md`.

**Favourite author** : a writer the reader singled out. The third of the three judgements, and the only one that crosses publishers : a reader follows a byline through whatever paper it appears in, which no subscription can express. It stars nothing and it changes nothing about the articles.

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
| `Indexer` | FTS5 for every article, Core Spotlight for what the reader chose |
| `Search` | The query language, and its compilation to SQL |
| `Enricher` | vectors, classification, rule execution |
| `Sync` | `CKSyncEngine` on the private database |
| `Notify` | Local notifications : what is worth saying, and the rules for saying it |
| `Place` | Where the reader says they read from : suggestions from MapKit, one fix from the device. `docs/technical/place.md` |
| `Automation` | App Intents, widgets, local MCP server on macOS |
| `Import` | OPML and service imports, exports |

SQLite is driven directly through GRDB. SwiftData is ruled out : the volume is large, the concurrency needs fine control, and FTS5 virtual tables need direct access.

GRDB is the only external dependency, and it stays that way. A package is added only where writing the equivalent ourselves would be unreasonable ; everything else comes from the system frameworks.

---

## 6. Local data model

| Table | Contents |
| ----- | -------- |
| `feed` | canonical URL, title, whether the reader singled it out, conditionality metadata (`etag`, `last_modified`), health, observed periodicity, local settings |
| `source_name` | what the reader calls one publisher. A row only where they wrote one : the groups themselves fall out of the addresses |
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
| feeds, publisher names, tags, rules, queries, settings | a few hundred | complete |
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

### Sharing a collection

A made collection may be shared with other iCloud users, who may file into it. Apple's own sharing carries it : a zone-wide `CKShare` on **one custom zone per shared collection**, never on the `Flong` zone, which holds everything and must never be handed over. The invitation goes through `ShareLink` and `CKShareTransferRepresentation` ; the participants are the system's to manage. A second `CKSyncEngine`, on the shared database, carries the collections the reader was invited to, and it sends as well as fetches.

**What travels is the excerpt the feed published, and never the article.** The article is not the reader's to hand anybody, and what a publisher puts in a feed for syndication is the part they chose to make public. The excerpt is already plain text at three hundred characters, so no markup crosses between accounts and there is nothing for a renderer to interpret.

**One list per participant**, chunked when it needs to be. Each person writes only their own and reads everybody else's, which is the shape the stream archives use and for the same reason : two people filing at once cannot collide, so there is no conflict to resolve. It follows that a participant takes back what they put in and nothing else. A shared collection therefore costs a handful of records rather than one per article.

**An address is truncated of the parameters the reader designated as secret**, by the device doing the writing and against its own keychain, since nobody else can know which of them were theirs. Nothing is removed on a guess : a parameter is as likely to select the feed or a filter as to identify the subscriber, which is why a canonical address keeps its query string. A cookie session is never sent.

**What arrives is not the reader's article.** It came from a feed they do not follow, it lives in a table of its own, and it is never counted unread, never purged, never indexed as theirs and never re-shared. Where they already hold the piece, their own copy is shown instead.

`docs/technical/collaboration.md` carries the design and the reasoning.

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

**Scheduling** : an interval derived from the median of the observed publication gaps, bounded between fifteen minutes and twenty-four hours, corrected by time of day for sources publishing on business hours. Manual per-feed override, set from the source's own editor, which offers a handful of intervals inside those bounds rather than a field of seconds.

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

A secret URL is treated as a secret in its own right : masked in the interface, redacted from exports by default, absent from error messages. Whether an address is one is the reader's to change afterwards, from the editor of the source, which is what lets an address pasted in the open be taken out of the database and out of the reader's iCloud without losing anything under it.

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

**Typography** : **amended**. This asked for control over typeface, size, leading and column width, and light, dark and sepia themes. What is built is **three themes**, chosen once and applied to the whole application rather than to the article alone, since a reader who asked to read on warm paper did not mean only inside an article :

| Theme | Faces | Colours |
| ----- | ----- | ------- |
| `Défaut` | Serif headlines over a sans body | The system's own, which it states none of |
| `Papier` | The same faces | Warm paper, with the contrast pulled back |
| `Solarized` | Monospace headlines, sans body | Ethan Schoonover's palette |

Light and dark stay the system's answer rather than becoming themes of their own, so each of the three states both and follows the device. Sepia is `Papier` under another name. The choice is carried between the reader's devices by the iCloud key-value store, like the body an article opens on, and never by a CloudKit record.

Size is Dynamic Type and belongs to the system. Leading and column width are not offered : the measure is one of the decisions the page makes rather than one it asks the reader about. `docs/technical/interface.md` records what a theme reaches and what stays the system's.

---

## 11. Indexing and search

### Two indexes

| Index | Scope | Technology | Target volume |
| ----- | ----- | ---------- | ------------- |
| full text | every local article | SQLite FTS5, contentless | hundreds of thousands |
| system | what the reader chose, and the front page | Core Spotlight | a few thousand |

Core Spotlight cannot serve as the primary index : `contentDescription` is capped at around three hundred characters, and the recommendation is to stay within a few thousand items per application, beyond which search performance degrades severely. It suits what the reader chose perfectly, with two immediate benefits : what the reader kept shows up in system Spotlight, and natural-language semantic search comes from the system.

### Lexical index

A contentless FTS5 virtual table, weighting title, standfirst, body and author, kept in step by triggers on the articles and their bodies. Contentless rather than external content : it holds an index and not a second copy of the articles, which is the point either way, and a row can be removed on its identifier alone. External content demands the exact original text back on every delete, and a cascade that has already removed the body has nothing to give back, which is how a full-text index quietly corrupts itself.

The `unicode61` tokenizer with diacritics removed, wrapped in `porter`. The stemmer is English, the only one SQLite ships, and it is close enough on French suffixes to be worth having ; a per-language index is what doing better would take. Language detection at ingestion, stored on the article.

A full rebuild is possible at any time, on the order of a minute over the target corpus.

### System index

Two things go into Core Spotlight, and each of them is chosen rather than collected.

**The articles the reader chose**, with title, excerpt, author, date, tags and thumbnail. There are five ways of choosing one. Three are about the article itself and are made one article at a time : starring it, writing on it, filing it in a collection. Two are made once and stand for everything that follows : singling out a publisher, singling out a writer. Everything else is a cache nobody chose, and a system-wide index of a cache is an index of things nobody asked for. The two favourites are deliberately wider than what a purge may not take : a judgement about a source or a writer earns an article a place in the system search without earning it a place a purge has to work around.

**A favourite is worth its two hundred and fifty most recent articles and no more**, counted per source and per writer. The three deliberate ways of choosing bound themselves, a reader marking a few thousand articles in years ; a favourite does not, a daily serving forty articles a day being fifteen thousand items within the year on its own. The cap is what keeps the budget above a budget rather than a hope : the index is then bounded by the number of favourites, which is the only quantity the reader controls. It costs them nothing they cannot reach another way, the full-text index covering every article ever stored. The cap is the system index's alone : the favourites' own collections hold everything, uncapped.

**The stories on the front page**, no more and no less, with their headline, their line, their subjects and the rooms covering them. A story is where the digest starts and it is what a reader watching a subject is actually looking for, so the system search has to be able to find one. They are not marks and they are not kept : they age off the page, and they age out of the index with it. They live in a Spotlight domain of their own, which is what makes `no more and no less` cheap : the page is written by emptying that domain and writing it again.

Deciding whether the index is up to date costs a pass over the chosen articles' identifiers and dates ; deciding that it is not costs their full texts as well. The first happens after every catch-up that brought something, the second almost never. `CSIndexExtensionRequestHandler` is implemented so Spotlight schedules reindexing itself under favourable conditions, device asleep or idle, outside the application lifecycle.

The Spotlight index is local and private, and is never shared between the devices of one account. Every device indexes on its own behalf.

### Semantic search

Over what the reader chose only, through Core Spotlight semantic search, falling back on vectors computed by the application and cosine similarity, which needs no particular index structure at this scale.

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
| **Built-in** | A question every reader's articles answer about themselves : starred articles, notes. Favourite sources asks it of the publisher instead, and the answer rides on the feed's record ; favourite authors asks it of the byline, and the answer is a record of its own | The state of one article, yes or no, on that article's own record |
| **Made** | Filled article by article | The pair, this article in that collection, as a field on the article's record |
| **Dynamic** | Described rather than filled | The description, and never what answers it |

Nothing new was needed in the store for any of it. A built-in one is a column ; a made one is a tag under a `collection/` root bound through `tag_binding`, which section 4 already described ; a dynamic one is the `saved_query` of section 5 holding a name and an expression of the query language of section 12. All three had been in the schema since v1.

**The dynamic one is the reason to have three.** It costs one small record whether it holds nothing or ten thousand articles, because a description is a description. It also has no membership to keep in step : it answers itself, at the moment it is asked, from whatever the reader has.

**Five built-in squares, and one of them is not a set of articles.** Three are judgements, each about a different thing : the star is about the piece, the favourite source about who printed it, the favourite author about who wrote it. Notes is the reader's own words. The fifth, **authors**, is a directory of every byline this device has read, and it is the only square on that page that opens on people rather than on articles ; the number under it counts names. It is not stored anywhere : the list is a question the articles answer about themselves, grouped on the row per person that sits beside each article, so nothing goes stale and there is no row standing for a writer who no longer signs anything here. That row exists because the `author` column holds a whole byline and a byline names two people as often as one ; the column keeps what the publisher wrote, and the people are written out beside it as an article is stored. `docs/technical/authors.md` sets out why an author is a name matched exactly and never a person guessed at.

**A favourite author is one record, and its deletion is the `no`.** The writers themselves are worked out from the articles, so there is nothing to send about the thousands nobody has an opinion on ; a reader following a few dozen bylines spends a few dozen records of the budget of section 7. The record is named after the writer, so two devices singling out the same person write one record between them, and the presence of the record is the whole of the answer.

**Made, never unmade.** A name arriving from another device is created ; a name absent from what arrived is not deleted. Deleting is therefore local until every device has been told by other means, which is the price of not carrying a tombstone for every name ever used. Membership is the other way round : what arrives about one article is the whole truth about it, so a collection missing from its list is one it was taken out of.

### Notifications

Everything Flong may interrupt the reader for is a switch in one panel, and every switch starts off.

**A panel from the bottom, beside the sources.** The sources and the subjects are panels too, opened from the same corner and built the same way : untitled, closed by a flick, and with the button a Mac needs since a Mac sheet cannot be flicked. This one was a line in the reader's menu leading to a screen of its own, which is two presses and a way back for one switch : a reader who turns a notice on is not going anywhere, they are answering a question and returning to what they were reading. The bell stands next to the sources in the leading corner of every section a reader reads in, and opens a short sheet over the page. The panel says nothing it does not have to : a heading over a single switch named the list it was heading, and a paragraph under it explained what a story is to somebody who has been reading a page of them.

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

**A headline is written to the rules a desk would apply.** It says in a few words what the group contains and makes somebody want to read it, in that order of importance : every word carries information, no jargon and no abstraction, a named actor and a verb of action before a general idea, the words a reader would look for first since it is read in a list and often cut short, and clarity before cleverness, wordplay needing a readership and an editorial line that a model writing for one stranger does not have. Twelve words is the ceiling and it is enforced, not merely asked for. Above all it never promises more than the articles say : the gap between a headline and what it delivers is what destroys the credit of a publication, and a page nobody signed has less of that credit to spend. The line beneath states the angle and answers what the headline had no room for, of who, what, where and why, in one or two sentences and never the headline again in other words. *When* is deliberately not among them : the model is shown no dates, so it invents rather than omits, and the page already says when a story arrived. `docs/technical/digest.md` sets out how each of those is checked.

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
- **The subjects**, as pills that scroll : the front page first, then the subjects the model filed the stories under, most covered first. **Amended** : this section asked for a day, week and month selector. A period is a question about the calendar, and nobody watching a subject asks it. The front page looks back three days, which is a story still worth a headline, and everything older stays reachable through unread, the collections and search.
- A story is under **several** subjects, or under none, in which case it is still on the front page and simply on no pill. Its subjects are shown above its headline, the way a rubric is set above a piece.
- The subjects have **two natures** : a catalogue of fifty standard sections, seeded at the first launch so a page reads sensibly on its first day, and the reader's own, theirs to add and to remove. The model files each story under one or two of them, with no way out of choosing, and writes none of its own. It was allowed one of its own where nothing it was shown fitted, and what came of that was a drift of near synonyms of the sections that already existed, in whichever language the articles happened to be in ; the catalogue was widened from thirteen instead, since a gap in a list nothing may go outside of is a story misfiled for ever.
- The subjects are a **vocabulary**, written once and kept. A story is filed into it once and keeps what it was given, and the reader may write subjects of their own, which the model files under like any other.
- A long press on a subject says more of this or less of this, on a score from minus three to three that starts at nought. A panel opened from the leading corner, beside the sources and the notices, lists every subject there is, including those no longer on the page, and sets each to down, nothing or up : what a reader says there is said about the page behind the panel, so the page stays where it is while they say it. The score orders the stories before their weight does, and orders the pills themselves. It stays on the device for now : `docs/technical/digest.md` says why it ought not to. Without a model there are no subjects and no pills, and the front page is entire ; a model that answers nothing leaves the subjects already on the page alone, rather than blanking a good page over a transient.
- **Amended : there is no tail.** This section asked for what grouped with nothing to sit under the stories as the ordinary articles it is. It did, and it was the wire drawn a second time : the section beside the digest already shows everything, newest first, read or not, so the bottom of the front page was a shorter copy of the page next door. A front page carries what is happening ; what merely arrived has a section of its own, and nothing is hidden by saying so.

The first story on the page runs its picture across the column, above a larger headline ; the others keep theirs to a square at the side. A page where every story is the same size is a list, and a list makes the reader do the ranking the digest exists to do.

**The top of the page takes the colours of that picture**, under the standard theme alone : the head of the digest, the bar over it and the dateline in it are washed in three bands read from the lead's own photograph, and the colour is spent by the time the photograph itself comes into view. The other two themes state what the page is printed on and a wash over either would be a second opinion about the paper ; the standard theme states nothing, which leaves it the one page a picture has room to speak on. Nothing at all where the reader has asked for more contrast. A story's own page does the same with its own picture, which is the one the row that was tapped was carrying, so the colour carries across the tap rather than starting again. `docs/technical/interface.md` records how the bands are read and why the colour is not the picture's own lightness.

Each story carries its name, one line saying what happened, the marks of the rooms talking about it rather than a count of them, the number of articles, the shape of their arrival and how long ago the last one came, said in the mark a revision wears and not in words, and set across the whole measure so that one edge holds it on every row whether the story carries a picture or not. An article row says the opposite thing the opposite way : the moment is written out, to the day and the minute, since a list of one morning's articles as twenty phrasings of the same hour is a list nobody can compare. Opening a story lists its articles ; opening an article reads it. Not a card : a rule, a headline, a line and the facts underneath.

The model names and summarizes ; without one, a story takes the title and standfirst of its most central article, and the page says which of the two it is, by a mark in front of the line and in no words : pressing that line says what was written and offers the article's own headline back. `docs/technical/digest.md` records how stories are grouped, and why it is not by the vectors of section 11.

### Common structure

**The page keeps itself up to date.** The window follows the store through `DatabaseRegionObservation`, so a change from anywhere reaches it : a background refresh, another device through `CKSyncEngine`, an archive read in. A burst settles before anything is read back, and the article list is left alone while an article is open. A clock every five minutes asks the publishers, which section 8's politeness then decides per feed, since following the store shows what has arrived and nothing in it asks for more. Every automatic trigger goes through one entry point that fetches, groups and reads the page back, so the front page gains stories from a background pass and from a clock tick and not only from a cold launch. A pull on the front page, and on no other, says now rather than soon : it fetches every feed and groups what arrived, and the page is read back once the control has retracted rather than under it. The wire has none, being a list of what has arrived. Asking without the gesture is no longer possible : `Actualiser` was a line in the reader's menu and went with it, so a Mac has no way to fetch by hand and relies, as this section has always said the page does, on the clock, the full pass at rest and the watcher that follows the store. While a phase is actually running, a line at the head of the front page names it and fills a rule where there is a real count to fill it with, and goes when there is nothing left to say ; `docs/technical/interface.md` sets out why it is in the pinned header and why it answers to no gesture.

**Amended.** This section asked for three levels, sidebar, list and article, shown as three columns on iPad and Mac. What is built shows one column at a time on every platform, under the system tab bar : the digest, the wire, the collections, and search, with the sources reached from the header. Two columns of chrome around an article are two columns of not reading, and the sections a sidebar was to hold are the sections the tab bar holds. Each section keeps its own navigation stack.

On macOS those same sections become a sidebar, drawn by the system for an adaptable tab view, since a Mac window keeps its sections at the side.

Views the sidebar was also to list, today, starred, tags, saved queries and individual feeds, are reached from the sources panel rather than from a permanent column.

### The sources

**Amended : grouped by publisher, and there is nothing to make.** This was a folder tree, and no screen ever let a reader plant one : the only folders that existed came out of an imported OPML file. A group is every feed served from one address, worked out from the addresses themselves, so it is right the moment a subscription lands, it cannot go stale and it never survives the last of its feeds. The reader writes a name over one where the address is not the name they use, and that name is the only thing about a group that is stored.

Every source sits under a heading, the ones alone under theirs included. A list where some rows are grouped and others are loose is a list where the reader cannot tell in advance where a source will be, and the heading is the only place a group is acted on : it opens a menu holding the naming and the whole of that publisher's articles.

The mark of a publisher stands once, at the head of its group, and the rows under it are desks with names and nothing more.

A source can be made a **favourite**, which is the reader saying this publisher is one of theirs. It is not the star an article wears : it stars nothing, it reorders nothing, and it changes nothing the front page ranks. It marks the row, and it fills a square on the collections page beside the starred articles, where the two are plainly different things.

An **author** can be made a favourite the same way, from the authors page or from the menu of an article they signed. It is the same kind of judgement about a different thing, and it is the only one that crosses publishers : a reader follows a byline through whatever paper it turns up in. Like the other two it stars nothing, and it fills a square of its own beside them.

A source can be **edited**, from its own menu : what it is called, the address it is served at and whether that address is a secret, which of its parameters are the reader's own, the site it belongs to, how often it is asked, and whether it is one of their favourites. The address is the one that matters. A publisher who moves their feed used to cost the reader everything under it, since the only repair was to stop following the source and follow it again ; editing the address moves the row and leaves the articles, the stars, the notes and the filings exactly where they are, here and on the reader's other devices, which are told where the source came from rather than that one went and another arrived. The health this section asks to be surfaced in the feed settings is on the same screen, and so is the way through to the address parameters. A source whose address is itself a secret is offered a new secret address rather than shown the one it has, and whether it is a secret at all is a switch beside the address, since a reader who pasted a per-subscriber address without saying so had otherwise no way of taking it back out of their own iCloud. `docs/technical/editing-a-source.md` sets out what a change of address drags along, and what it deliberately leaves alone.

A source can also be **removed**, from a swipe on its trailing edge or from its long press, and a whole publisher from its heading's menu, which is the second thing that menu does. It is the one thing in this panel that cannot be undone, so it asks first, and the sentence it asks with names what goes rather than warning in the abstract : the articles go with the source, the ones the reader starred, wrote on or filed included. What goes with them is everything that was only there because of that source, here and in the reader's iCloud, which is what carries the removal to their other devices. `docs/technical/removing-a-source.md` sets out what is reached, what is deliberately not, and why.

The digest, a story and an article are set as a page rather than as a control panel : one column held to a readable measure, serif headlines, hairline rules, no cards and no boxes. Liquid Glass belongs to the navigation layer, which is the system's own bar. The application draws it of its own in two places and both are that same rule : the subject pills, which are controls floating over the page, and the credit in the corner of a picture, which has to stay legible over an image nobody chose. `docs/technical/interface.md` records the design and what was rejected.

### The wire

**Amended.** This section asked for an unread queue as one of the three levels. The section beside the digest shows **everything, newest first, read or not**, broken by day. A queue is a thing to get to the end of, and a reader watching a subject is not trying to finish anything ; what they want is to see what came in and where they left off. Unread on its own remains a view, in the sources list, for whoever does want it, and the count of unread articles still rides on the section.

### List

Adjustable density, a one- to three-line excerpt, an optional thumbnail, the publisher an article came from, optional mark-as-read on scroll, configurable swipe gestures, multiple selection and batch actions.

**The publisher and not the feed.** A row says `Le Monde`, whichever of its desks the article arrived through, and wears the one mark that paper drew. A reader following three desks of one paper was meeting three names down one page and having to work out that they were one paper ; which desk it was is a detail of how the paper publishes, and it stays in the sources list where a subscription is managed.

The picture an article carries is taken from the feed, or failing that from the first picture in the body, and only its address is stored : the file stays the publisher's and is asked for when a screen shows it. **Every picture the digest shows is credited** to the publisher whose article it arrived with : their name, in the corner of the picture, on a pill of glass, and never a byline, since what reaches a feed is where a picture came from and never who made it. An article row carries none and needs none, its own headline already naming the publisher. `docs/technical/ingestion.md` records the order, `docs/technical/interface.md` how the page uses it.

### Article

Reader mode when the reader has chosen it, a switch to the feed content or the web view, the choice remembered and carried between devices by the iCloud key-value store rather than by a CloudKit record, keyboard navigation on Mac and iPad, a constant action bar : read, star, tag, share, open in the browser.

**Presented over the window rather than pushed onto a section.** An article on a section's stack is an article under the tab bar, which is a row of places to go laid across the one thing that asks to be read with nothing else in the way. It grows out of the row that opened it and is put down with a cross : the page it came from never went anywhere, so there is nothing to go back to.

**It opens on the picture the row was carrying**, run across the head above the headline, edge to edge and under the controls, at its own height rather than cropped : a page is the one place a photograph is looked at rather than glanced at. The same picture is taken out of the body where it came from there, so the page does not show it twice.

### Search

A single field accepting the query language, live results, and saving a query straight from the field. The switch between stream and library is gone with the library : there is one corpus, and `is:starred`, `is:collected` and `is:annotated` narrow it to what the reader marked.

### macOS

A window whose sections sit in a sidebar, complete keyboard shortcuts, a menu bar, customizable toolbar items, multiple windows, and inbound and outbound drag and drop.

### Widgets and extensions

Unread, collection and saved-query widgets. A Share extension for subscribing and for marking. Controls for Control Center and the Lock Screen.

### First launch

An OPML import or an import from an existing service offered right away, an optional starter set of feeds, a one-sentence explanation of what a mark is and why it never disappears, and no account creation.

### Where the reader is

Under the reader's own face, beside their name : **a town and a country**, optional, empty until they answer, and never asked for twice. It is kept because the region somebody reads from is a fact about them, like their name and like the theme they read in, and it travels between their devices through the key-value store with the rest of what they chose.

Two ways to answer it. **Typing is the road** : the town is completed by MapKit as the reader types, the list is held to towns and countries by an address filter, and the one suggestion they choose is resolved into fields rather than read off its own display text. It needs no permission, and it works on a Mac with no receiver in it. **The device is the shortcut** : one fix, asked for at the moment the button is pressed and never before, turned into a town and forgotten.

**What is kept is a name and never a coordinate.** A latitude is the reader's street, it would travel to their iCloud with everything else here, and nothing that will read this wants more than a region. The country's ISO code is kept beside its name, since a name arrives translated and a code does not, and matching on a translated string is how a preference set on one device stops working on the next.

A refusal leaves the reader in front of the search, which is the thing that works in every case, and leaves whatever they had chosen by hand alone. `docs/technical/place.md` records the two paths, what is sent to Apple while they choose, and what is not.

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

**OPML import**, including the common proprietary attributes, walking the nesting for every feed at the bottom of it and tolerating malformed files. The tree itself is not kept : a source belongs to the publisher serving it, which its own address already says.

**Import from an existing service** : FreshRSS and Miniflux through their API, Feedbin and Feedly through theirs. Subscriptions, labels, stars and read states are retrieved, after which Flong runs on its own. Folders are read for the subscriptions inside them and not kept, as an OPML file's tree is not. No permanent synchronization is kept with the origin service.

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
- Location asked for only at the moment the reader presses the button that uses it, kept as a town and a country and never as a coordinate, and never sent anywhere but Apple's own geocoder while they are choosing.
- A privacy policy and an App Store privacy nutrition label consistent with the above : no collection.

### Deleting everything

There is no account to close, so there is a command that deletes everything instead. It sits at the foot of the reader's panel in a card of red glass rather than in the grouped form the settings sit in, it names what it will delete before it does it, and it reaches all six places that hold something : the database, the keychain, the key-value store, the Spotlight index, the record zone and the archive in iCloud Drive. Fewer than all six is a pause rather than a reset, since the last three would fill the first three back up at the next exchange.

It is not the purge of section 13, which frees space and spares everything marked. This deletes what that one exists to protect.

**It cannot reach another device.** One that still holds the subscriptions finds the zone gone, takes that as `zoneNotFound`, recreates it and sends its copy back, which is the correct repair path for a zone lost for any other reason and is the price of having no server. The alert says so in a sentence before the reader confirms. `docs/technical/erasure.md` records the order and why it is that order.

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
| Core Spotlight caps | design | use restricted to what the reader chose and to one page of stories, with each favourite worth its two hundred and fifty most recent articles so that a prolific publisher cannot fill the index on its own |
| model divergence between devices | data | identifier and revision stored, local recomputation rather than mixing |
| drift towards a mandatory Mac | product | no macOS-exclusive feature allowed, blocking install test on an iPhone alone |
| traffic multiplied by device count | externality | systematic HTTP conditionality, pseudo-random stagger |
| third-party dependency for newsletters | product | flagged in the interface, never mandatory |
| iCloud quota full | user | `quotaExceeded` detected, an explicit message, a purge offered |
