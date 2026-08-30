# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Xcode project targeting iOS, iPadOS and macOS 26.0, from the multiplatform SwiftUI template.
- String catalog with English as the source language and French translations.
- `swift-format` configuration and a shared `Flong` scheme so builds and formatting are reproducible outside Xcode.
- Issue and pull request templates.
- Product and technical specification in `docs/specification.md`, the reference for every design decision.
- Project conventions in `CLAUDE.md`, and the Google Reader API reference kept in `docs/technical/` for the FreshRSS import.
- MPL-2.0 license, with the source notice carried by every file.
- SQLite storage through GRDB, holding the local data model of the specification behind versioned migrations, with UUIDv7 identifiers that sort by creation time.
- Subscriptions : following a feed by its canonical URL, with folders, renaming, moving and unsubscribing, and a batch path that lands a whole import in one transaction.
- OPML import, tolerant of the malformed files exporters produce, preserving the folder tree and reporting the lines it could not use, with a screen listing the subscriptions it brought over.
- Private and authenticated feeds : a per-subscriber secret address, HTTP Basic, a bearer token or a fixed header, kept in the keychain and propagated by iCloud Keychain, never in the database, a log, an error message or an export.
- Sessions on sites the reader subscribes to : signing in happens from the article's own menu, on the site's own page in a web view, only the session it leaves is kept, one sign-in covers every feed of the site, it is sent to that site and no other, and a session the site has ended says so rather than quietly serving teasers.
- Full-text extraction : an article opens on whichever version the reader last chose, carried between their devices by the iCloud key-value store, and asking for the whole one fetches the page behind it once, pulls the article out of the navigation, sidebars, share bars and comments around it, and keeps it beside the feed's version.
- HTML parsing and whitelist sanitization, written without a dependency, dropping scripts, frames, forms and tracking pixels, and resolving every address against the article before vetting its scheme.
- Feed parsing for RSS 0.9x, 1.0 and 2.0, Atom 1.0, JSON Feed 1.1 and h-feed, with feed discovery from a page, tolerance for the malformed feeds publishers serve, and a corpus of them under test.
- Conditional fetching with a token bucket per host, `Retry-After` honoured, backoff with jitter, a body cap enforced while streaming, and a refresh interval derived from each feed's own publication history.
- Ingestion of fetched feeds into the store, recognizing articles already seen, and the same article arriving through two feeds of one newsroom, which is kept but shown once, refreshing them without touching read or starred state, tracking feed health and quarantining what stays broken, with retention by age and by volume, and keeping the address of the picture that stands for each article, stated by the feed or taken from its body.
- The reading interface, on iPhone, iPad and Mac : one column at a time under the system tab bar, a sidebar on Mac, each section keeping its own stack, a wire of everything as it arrives broken by day beside the digest, carrying no count of what is unread, a read article marked by a tick at the end of its headline rather than dimmed, with an isolated web view following the system appearance, reading and starring, marking a view read, adding a feed from the address of a site, and refreshing on returning to the foreground or on a pull.
- Full-text index over every stored article, kept in step by triggers, insensitive to accents and to endings, rebuildable at any time, with the language of an article detected on the device as it arrives.
- Query language with fields, states, dates, brackets and exclusion, parsed into a tree and compiled to SQL with every value bound, understanding the FreshRSS syntax, and ranking results by relevance when the index can answer the whole query.
- Search from the article list, following what is typed, completing feed and folder names, and held to the targets of the specification by a test over 125,000 articles.
- Library : starring or annotating an article copies it whole, so it survives the purge of the stream and the disappearance of its source, and what is kept is handed to Spotlight and found in the system search.
- Synchronization between a reader's devices through their own private CloudKit database, told of another device's changes by a silent push, carrying subscriptions, kept articles and read states compacted into one record per month, keeping what the server says about each record so a second save is not refused, with catch-up headers for a device that was switched off, and iCloud's refusals surfaced rather than retried blindly.
- Long work done in resumable batches and in the background : the feeds an import left unfetched, and a vector for every kept article, computed on the device and shared between them, which lets the library be searched by meaning rather than by words.
- A digest as the main screen : articles grouped into stories, the ones several rooms are covering right now shown as they arrive, a room being a newsroom rather than a feed so a paper with a feed per desk counts once, named and summarized on the device by the system model in the reader's own language whatever language the articles are in, each one stating the rooms, the count and the shape of the arrival it rests on.
- Subjects across the page, found by the system model and shown as pills pinned at the head of it and as a rubric above each headline : a vocabulary written once and kept, which a story is filed into once, one story per call and the answer chosen from the vocabulary itself, and which the reader may add their own subjects to.
- A long press on a subject says more of this or less of this, on a score from minus three to three that orders the stories before their weight does, and orders the pills themselves.
- A reader's menu in the digest, holding every subject there is with what was said about each, including the ones that have fallen off the page, a way to add and remove subjects of their own, and the command to write the digest again.
- The language a summary was asked in travels with it, so changing the language of a device rewrites the page rather than leaving it in a language its reader no longer reads, a summary that comes back in the wrong language is dropped for the article's own headline, and a command at the foot of the sources list asks the model to write it all again.
- The sources list says when there is no model on this device, and which of the three reasons it is, so a page named after its own articles is not mistaken for a broken one.
- The digest is titled with the day's date rather than with its own name, and refreshes on a pull and on returning to the foreground, the Mac keeping the command in its toolbar.
- An editorial page rather than a control panel : one readable column, serif for what was written and sans for what the application says about it, hairline rules in place of cards, and Liquid Glass left to the system's own navigation bar, where Apple's guidance keeps it.
- Pictures on the page : the first story runs its picture across the column and the others keep one beside them, all at three by two, decoded at the size they are drawn and cached on disk rather than fetched twice.
- The mark of each source beside its name, in the sources list and on every article row, and in place of the count of rooms on a story, taken from what the feed states or from the well-known paths a site keeps one at, and falling back to a generic mark rather than a hole.
