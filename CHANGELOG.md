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
- HTML parsing and whitelist sanitization, written without a dependency, dropping scripts, frames, forms and tracking pixels, and resolving every address against the article before vetting its scheme.
- Feed parsing for RSS 0.9x, 1.0 and 2.0, Atom 1.0, JSON Feed 1.1 and h-feed, with feed discovery from a page, tolerance for the malformed feeds publishers serve, and a corpus of them under test.
- Conditional fetching with a token bucket per host, `Retry-After` honoured, backoff with jitter, a body cap enforced while streaming, and a refresh interval derived from each feed's own publication history.
- Ingestion of fetched feeds into the store, recognizing articles already seen, refreshing them without touching read or starred state, tracking feed health and quarantining what stays broken, with retention by age and by volume.
- The reading interface : sidebar, article list and article, on iPhone, iPad and Mac, with an isolated web view following the system appearance, reading and starring, marking a view read, adding a feed from the address of a site, and refreshing on returning to the foreground or on a pull.
- Full-text index over every stored article, kept in step by triggers, insensitive to accents and to endings, rebuildable at any time, with the language of an article detected on the device as it arrives.
- Query language with fields, states, dates, brackets and exclusion, parsed into a tree and compiled to SQL with every value bound, understanding the FreshRSS syntax, and ranking results by relevance when the index can answer the whole query.
- Search from the article list, following what is typed, completing feed and folder names, and held to the targets of the specification by a test over 125,000 articles.
- Library : starring or annotating an article copies it whole, so it survives the purge of the stream and the disappearance of its source, and what is kept is handed to Spotlight and found in the system search.
- Synchronization between a reader's devices through their own private CloudKit database, carrying subscriptions, kept articles and read states compacted into one record per month, with catch-up headers for a device that was switched off, and iCloud's refusals surfaced rather than retried blindly.
- Long work done in resumable batches and in the background : the feeds an import left unfetched, and a vector for every kept article, computed on the device and shared between them, which lets the library be searched by meaning rather than by words.
