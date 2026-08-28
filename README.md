# Flong

A native [FreshRSS](https://www.freshrss.org/) client for iOS, iPadOS and macOS, written in Swift with SwiftUI and SwiftData.

> Status : early. The Google Reader API client is in place and covered by tests. The data layer and the interface are next.

## Platforms

| Platform | Minimum version |
| -------- | --------------- |
| iOS      | 26.5 |
| iPadOS   | 26.5 |
| macOS    | 26.5 |

A single SwiftUI codebase serves the three platforms.

## Requirements

- Xcode 26.5 or later
- A FreshRSS instance with its API enabled

## Building

Open `Flong.xcodeproj` in Xcode and run the `Flong` scheme, or build from the command line :

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'generic/platform=iOS Simulator'
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'platform=macOS'
```

The `DEVELOPER_DIR` export is only needed when `xcode-select` points at the Command Line Tools rather than at Xcode.

## Connecting to FreshRSS

Flong uses the Google Reader compatible API that FreshRSS exposes at `/api/greader.php`. Two settings are needed on the instance :

1. **Settings, Authentication** : tick *Allow API access for external clients*.
2. **Profile** : set an *API password*. It is distinct from the web password, and it is the one Flong asks for.

The instance URL, the username and the API password are all Flong needs. Credentials are stored in the system keychain and never written anywhere else.

## Backends

FreshRSS is the only supported service today. Backend access sits behind a provider abstraction, so other services speaking the same Google Reader API can be added without touching the interface.

## Localization

The interface is authored in English and translated to French. All strings live in `Flong/Localizable.xcstrings`.

## Documentation

| Document | Contents |
| -------- | -------- |
| [`CLAUDE.md`](CLAUDE.md) | Working conventions : architecture, guidelines, git and release workflow |
| [`CHANGELOG.md`](CHANGELOG.md) | Change history, following [Keep a Changelog](https://keepachangelog.com/) |
| [`docs/technical/freshrss-api.md`](docs/technical/freshrss-api.md) | The Google Reader API surface Flong relies on |

## License

Flong is released under the [Mozilla Public License 2.0](LICENSE). Modified Flong files must be published under the same license, while the rest of a larger work may carry another one.

Copyright (C) 2026 François Rousselet.
