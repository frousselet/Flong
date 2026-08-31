# Flong

A feed reader for iOS, iPadOS and macOS, written in Swift with SwiftUI and SQLite.

No server, no account, no hosting. Every device collects the feeds itself and keeps them in a local database ; what you choose to keep propagates through your own private CloudKit database.

> Status : early. Flong opens on a digest of what is happening rather than a list of what arrived, follows and fetches feeds, lets you read and search them by words or by meaning, keeps what you star, and carries your subscriptions, kept articles and read states between your own devices through iCloud.

## Ideas

**The main screen is a digest, not a list.** Its unit is the story : several articles, from several rooms, about one thing. What several rooms are covering right now is shown as it arrives, and what grouped with nothing is still there underneath. The system model sorts the page into subjects you can narrow it to. An aggregator shows what arrived and leaves you to work out what matters.

**Every article you have ever received stays, and so does what you said about it.** There is one notion of an article and no second copy of anything. Star one, write on one, file one in a collection, and that mark is carried on the article itself : it follows you to your other devices, and an article carrying one is never purged, whatever you ask the store to free.

**Your sources are grouped by publisher, and there is nothing to file.** A paper with a feed per desk is one heading, worked out from the address it serves them at, so the list is organized the moment you subscribe and never goes stale. Every article says the publisher it came from and wears the one mark that publisher drew, rather than naming whichever desk it happened to arrive through. Call a publisher what you call it rather than what its address says, and make one a favourite when it is one of yours : a favourite source is not a starred article, and the two sit as separate squares in your collections.

**Sources you pay for stay readable.** A per-subscriber feed address, HTTP Basic or a token, kept in the keychain. For a site whose articles sit behind a wall, sign in on its own page and Flong fetches the rest as you : it never holds your password.

**A truncated article is completed from its page.** Most feeds send a standfirst and a link. An article opens on what its feed sent ; ask for the whole one and Flong fetches the page behind it, once, and keeps what it finds beside the feed's version.

**Search is genuinely indexed.** A full-text index over the whole local corpus, a query language with operators, and semantic search over what you marked, through Spotlight.

**Enrichment happens on the device.** Classification, tagging and summaries come from the system model, in your own language whatever language the articles are in, and no article content is sent anywhere.

**It is set like a page, not like a control panel.** One column at a time, held to a readable measure, hairline rules, no cards and no boxes. Liquid Glass stays in the navigation layer, where Apple puts it, apart from the subject pills and the credit in the corner of a picture.

**Three themes, and they reach everything.** `Défaut` is the system's own colours set throughout in sans serif ; `Papier` sets headlines in serif on warm paper with the contrast pulled back ; `Solarized` is Ethan Schoonover's palette with headlines in monospace. Each states both appearances and follows the device, the rendered article included. The choice is made under your own face in the reader's panel, and it follows you to your other devices.

## Screenshots

| The digest | A subject | A story |
| ---------- | --------- | ------- |
| ![The digest on iPad](docs/images/digest-ipad.png) | ![The page narrowed to one subject](docs/images/topic-ipad.png) | ![A story on iPad](docs/images/story-ipad.png) |

The pills are the subjects the system model filed the page under, pinned at its head. Tapping one narrows the page to it ; the others stay, so there is always a way back. A long press says more of this, or less of this, and the page reorders itself.

| An article | Stream | Sources |
| ---------- | ---- | ------- |
| ![An article on iPad](docs/images/reader-ipad-light.png) | ![Everything as it arrives, on iPad](docs/images/live-ipad.png) | ![The sources on iPad](docs/images/sources-ipad.png) |

The stream carries a bar per day over the last thirty, pinned at its head. It scrolls itself to whichever stretch the reader has scrolled the list into, and the day at the top of the list is the wide bar.

The same page on iPhone, where the sections sit in the system tab bar and search has its own place in it :

| The digest | A story | Search |
| ---------- | ------- | ------ |
| ![The digest on iPhone](docs/images/digest-iphone.png) | ![A story on iPhone](docs/images/story-iphone.png) | ![Search on iPhone](docs/images/search-iphone.png) |

Rendered articles follow the system appearance, light and dark :

![The same article in dark mode](docs/images/reader-ipad-dark.png)

The feeds shown are made up, every address in them points at `example.com`, and the pictures are generated : nothing here belongs to anybody.

## Platforms

| Platform | Minimum version |
| -------- | --------------- |
| iOS      | 26.0 |
| iPadOS   | 26.0 |
| macOS    | 26.0 |

A single SwiftUI codebase serves the three platforms, and no feature exists on macOS alone. The sections sit in the tab bar on iPhone and iPad, and in a sidebar on Mac. An iCloud account is needed to synchronize between devices, never to use the application.

## Requirements

- Xcode 26.5 or later
- An iCloud account, only to synchronize between devices : Flong is fully usable on one device without one

## Building

Open `Flong.xcodeproj` in Xcode and run the `Flong` scheme, or build from the command line :

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'generic/platform=iOS Simulator'
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'platform=macOS'
```

The `DEVELOPER_DIR` export is only needed when `xcode-select` points at the Command Line Tools rather than at Xcode.

## Dependencies

| Package | Use |
| ------- | --- |
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite access, migrations, and the FTS5 full-text index |

Everything else comes from the system frameworks.

## Privacy

No data leaves the device, apart from the private CloudKit database, the requests to the feeds themselves, and the pictures those feeds point at, which are asked for from the publisher when a screen shows one. No telemetry, no tracker, no third-party service active by default. Feed credentials and secret feed URLs live in the keychain only, and never appear in the database, in an export, or in a log.

There is no account to close, so the reader's panel holds a danger zone that deletes everything instead : the database, the keychain, the preferences, the Spotlight index, the CloudKit record zone and the archive in iCloud Drive. Another device that still holds the subscriptions will put its own copy back, which the confirmation says before the reader confirms.

## Other services

Flong is not a client for any service. FreshRSS, Miniflux, Feedbin and Feedly are supported as one-shot import sources only : subscriptions, labels, stars and read states are retrieved once, after which Flong runs on its own. Their folders are read for the subscriptions inside them and not kept, since Flong groups sources by the publisher serving them.

## Localization

The interface is authored in English and translated to French. All strings live in `Flong/Localizable.xcstrings`.

## Documentation

| Document | Contents |
| -------- | -------- |
| [`docs/specification.md`](docs/specification.md) | The product and technical specification : the reference for every decision |
| [`CLAUDE.md`](CLAUDE.md) | Working conventions : architecture, guidelines, git and release workflow |
| [`CHANGELOG.md`](CHANGELOG.md) | Change history, following [Keep a Changelog](https://keepachangelog.com/) |
| [`docs/technical/feed-identity.md`](docs/technical/feed-identity.md) | How a feed is identified, and what happens when the same address is subscribed twice |
| [`docs/technical/opml.md`](docs/technical/opml.md) | What the OPML import reads, and how it copes with a malformed file |
| [`docs/technical/html.md`](docs/technical/html.md) | How feed HTML is parsed, and the whitelist it is reduced to |
| [`docs/technical/extraction.md`](docs/technical/extraction.md) | How the rest of a truncated article is fetched from its page |
| [`docs/technical/credentials.md`](docs/technical/credentials.md) | How a feed you pay for proves you are entitled to it |
| [`docs/technical/feed-formats.md`](docs/technical/feed-formats.md) | The formats Flong reads, and what it does with a broken one |
| [`docs/technical/fetching.md`](docs/technical/fetching.md) | How feeds are asked for, and how publishers are treated |
| [`docs/technical/ingestion.md`](docs/technical/ingestion.md) | What happens between a fetched feed and the store, and what bounds it |
| [`docs/technical/search.md`](docs/technical/search.md) | The index, the query language, and why nothing typed into it is ever run |
| [`docs/technical/marks.md`](docs/technical/marks.md) | What a mark is, why the library went, and what Spotlight is told |
| [`docs/technical/sync.md`](docs/technical/sync.md) | What travels between devices, what never does, and why the record budget shapes it |
| [`docs/technical/erasure.md`](docs/technical/erasure.md) | What deleting everything reaches, in which order, and what it cannot promise |
| [`docs/technical/notifications.md`](docs/technical/notifications.md) | What Flong may interrupt you for, and the rules it interrupts you under |
| [`docs/technical/background.md`](docs/technical/background.md) | How long work survives being interrupted, and how the marked articles are searched by meaning |
| [`docs/technical/digest.md`](docs/technical/digest.md) | How articles become stories, and why not with the vectors |
| [`docs/technical/interface.md`](docs/technical/interface.md) | How the interface is set, where Liquid Glass is allowed, and what was rejected |
| [`docs/technical/freshrss-api.md`](docs/technical/freshrss-api.md) | The Google Reader API surface, kept for the FreshRSS import |

## License

Flong is released under the [Mozilla Public License 2.0](LICENSE). Modified Flong files must be published under the same license, while the rest of a larger work may carry another one.

Copyright (C) 2026 François Rousselet.
