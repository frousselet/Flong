# Flong

<img src="docs/images/icon.png" alt="The Flong icon" width="128" align="right">

A feed reader for iOS, iPadOS and macOS, written in Swift with SwiftUI and SQLite.

No server, no account, no hosting. Every device collects the feeds itself and keeps them in a local database ; what you choose to keep travels between your own devices through your private CloudKit database.

> **Status : early.** Flong follows feeds, opens on a digest of what is happening rather than a list of what arrived, lets you read and search, and carries your subscriptions, your marks and your read states between your devices.

## What it does

**The front page is a digest, not a list.** Its unit is the story : several articles, from several rooms, about one thing. An aggregator shows what arrived and leaves you to work out what matters.

**The page is sorted into subjects.** Pills at its head narrow it to one of them, and a long press asks for more of this, or less of this.

**Sources are grouped by publisher.** A paper with a feed per desk is one heading, worked out from the address it serves them at, so the list is organized the moment you subscribe.

**You can follow a writer rather than a paper.** Every byline your feeds have signed is searchable, and singling one out gives you everything that person wrote, wherever it appeared.

**A source, or a writer, can tell you when it publishes.** Ask it of a newsletter, a blog or a colleague, and every article they put out is announced as it arrives ; ask it of a person and you follow them wherever they write. The front page is the press covering one thing ; this is the one voice you did not want to miss. Asking both ways about the same article still tells you once.

**What you mark stays.** Star an article, write on it, file it in a collection : the mark rides on the article itself, follows you to your other devices, and no purge ever touches it.

**Search takes a sentence.** Ask for the articles from Le Monde about the rentrée scolaire and that is what you get : the sentence is read on your device into a paper, a subject, a date, and it tells you what it understood. It works without Apple Intelligence too. The section opens with the cursor in the field, suggests what is worth looking for this morning from what your feeds are full of, and keeps what you searched for so you never type it twice. Full text over the whole local corpus, and what you marked reaches Spotlight.

**Sources you pay for stay readable.** A per-subscriber address, HTTP Basic or a token, kept in the keychain and never in the database, an export or a log.

**A collection can be shared**, through the system's own share sheet. What travels is the excerpt the feed published, never the article, because the article is not yours to hand anybody.

**Enrichment happens on the device.** Headlines, summaries and filing come from the system model, in your own language whatever language the articles are in, and no article content is sent anywhere.

**It is set like a page**, not like a control panel : one column, a readable measure, hairline rules, serif headlines over a sans body. Three themes, each stating both appearances.

## Screenshots

| The digest | A story | An article |
| ---------- | ------- | ---------- |
| ![The digest](docs/images/digest-iphone.png) | ![A story](docs/images/story-iphone.png) | ![An article](docs/images/article-iphone.png) |

| The stream | Search | The same page, in the dark |
| ---------- | ------ | ------------------------- |
| ![Everything as it arrives, day by day](docs/images/stream-iphone.png) | ![A search across the whole corpus](docs/images/search-iphone.png) | ![The digest in dark mode](docs/images/digest-dark-iphone.png) |

The feeds shown are made up, every address in them points at `example.com`, and the pictures are generated : nothing here belongs to anybody.

## Platforms

iOS, iPadOS and macOS, 26.0 or later.

One SwiftUI codebase serves the three, and no feature exists on macOS alone : the sections sit in the tab bar on iPhone and iPad, and in a sidebar on Mac. An iCloud account is needed to synchronize between devices, never to use the application.

## Building

Xcode 26.5 or later. Open `Flong.xcodeproj` and run the `Flong` scheme, or build from the command line :

```bash
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'generic/platform=iOS Simulator'
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'platform=macOS'
```

[GRDB](https://github.com/groue/GRDB.swift) is the only dependency, for SQLite access, migrations and the full-text index. Everything else comes from the system frameworks.

## Privacy

Nothing leaves the device but your own private CloudKit database, the requests to the feeds themselves, and the pictures those feeds point at. No telemetry, no tracker, no third-party service.

Feed credentials and secret feed addresses live in the keychain only. Where you say you read from is the name of a town and the code of a country, never a coordinate.

There is no account to close, so the reader's panel deletes everything instead : the database, the keychain, the preferences, the Spotlight index, the CloudKit zone and the archive.

## Other services

Flong is not a client for any service. FreshRSS, Miniflux, Feedbin and Feedly are one-shot import sources : subscriptions, labels, stars and read states are read once, after which Flong runs on its own.

## Documentation

| Document | Contents |
| -------- | -------- |
| [`docs/specification.md`](docs/specification.md) | The product and technical specification : the reference for every decision |
| [`docs/technical/`](docs/technical/) | One page per subject : feed identity, fetching, ingestion, search, marks, sync, sharing, the digest, the interface, erasure |
| [`CHANGELOG.md`](CHANGELOG.md) | Change history, following [Keep a Changelog](https://keepachangelog.com/) |
| [`CLAUDE.md`](CLAUDE.md) | Working conventions : architecture, guidelines, git and release workflow |

The interface is authored in English and translated to French. All strings live in `Flong/Localizable.xcstrings`.

## License

Flong is released under the [Mozilla Public License 2.0](LICENSE). Modified Flong files must be published under the same license, while the rest of a larger work may carry another one.

Copyright (C) 2026 François Rousselet.
