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
