# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flong is a feed reader for iOS, iPadOS and macOS, written in Swift 6 with SwiftUI, storing everything in SQLite through GRDB.

There is no server, no account and no backend service. Every device collects the feeds itself, keeps them in a local database, and propagates the retained data through the user's private CloudKit database. The product rests on a clean split between the **stream**, a disposable local cache rebuildable from the sources, and the **library**, what the user chose to keep : frozen, synchronized and never purged.

**`docs/specification.md` is the reference.** It carries the product and technical decisions, the budgets and the milestones. Read it before designing anything, and update it in the same commit when a decision changes. When this file, `README.md` or a page of `docs/technical/` disagrees with the specification, the specification wins.

A remote service is only ever a one-shot import source (specification, section 19). Flong never keeps a permanent link with FreshRSS, Miniflux, Feedbin or Feedly.

## Development Commands

`xcode-select` on this machine points at the Command Line Tools, so every `xcodebuild` and `xcrun` invocation needs `DEVELOPER_DIR` (or a one-off `sudo xcode-select -s /Applications/Xcode.app`) :

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### Building

```bash
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'generic/platform=iOS Simulator'
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'platform=macOS'
xcodebuild -list -project Flong.xcodeproj          # Targets, configurations and schemes
xcrun simctl list devices available                # Pick a simulator for -destination
```

### Testing

```bash
xcodebuild test -project Flong.xcodeproj -scheme Flong \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skip-testing:FlongUITests
xcodebuild test -project Flong.xcodeproj -scheme Flong \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlongTests/MigrationTests
```

Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. UI tests still use XCTest, which XCUITest requires.

### Formatting

```bash
xcrun swift-format lint --recursive --strict Flong FlongTests FlongUITests   # Fails on any violation
xcrun swift-format format -i --recursive Flong FlongTests FlongUITests       # Fix in place
```

Configuration lives in `.swift-format` (4 spaces, 120 columns). There is no CI yet, so this check is local only : run the formatter before committing.

## Architecture

### Target layout

The app target uses an Xcode synchronized file group, so a new file placed in `Flong/` joins the target with no `project.pbxproj` edit. Directories carry the architecture, one per module of section 5 of the specification :

| Directory | Contents |
| --------- | -------- |
| `Flong/App/` | App entry point, root view, app-wide environment objects |
| `Flong/Fetcher/` | Outgoing requests, HTTP conditionality, politeness, scheduling |
| `Flong/Parser/` | RSS, Atom, JSON Feed, h-feed, discovery, normalization |
| `Flong/Sanitizer/` | Whitelist HTML sanitization |
| `Flong/Extractor/` | Full-text extraction, reader mode |
| `Flong/Store/` | Database setup, migrations, records, queries, purge |
| `Flong/Indexer/` | FTS5 for the stream, Core Spotlight for the library |
| `Flong/Search/` | The query language : lexer, parser, and the compiler that turns a tree into SQL |
| `Flong/Enricher/` | Vectors, classification, rule execution |
| `Flong/Sync/` | `CKSyncEngine` on the private database |
| `Flong/Automation/` | App Intents, widgets, local MCP server |
| `Flong/Import/` | Reading a subscription list or an export back in, and writing one out |
| `Flong/Features/` | One directory per screen area, each holding its views |
| `Flong/Support/` | Logging and cross-cutting helpers |
| `FlongTests/` | Swift Testing unit tests |
| `FlongUITests/` | XCUITest suites |

A module directory is created when its first real file lands, not before.

### Key patterns

- **No external dependency unless it is indispensable** : the system frameworks come first, and a package is added only when writing the equivalent ourselves would be unreasonable. GRDB is the only one today, and it earns its place by replacing the connection pool, the migrator, the typed row decoding and the change observation the store would otherwise have to own. Adding another one is a decision to put to the user, never a default.
- **Storage is GRDB, never SwiftData** : the corpus reaches 125,000 articles, concurrency needs fine control, and the FTS5 virtual table needs direct SQL. Schema changes go through a numbered `DatabaseMigrator` registration, never an edit of an existing migration once it has shipped.
- **Technical keys are UUIDv7**, so identifiers sort by creation time and indexes stay lightly fragmented. Remote identity stays separate : an article is matched by its GUID, or failing that by the pair of link and publication date.
- **A feed is identified by its canonical URL** : everything that creates a subscription goes through `FeedURL.canonical(_:)`, never through a raw string, otherwise two spellings of one address become two rows and every article shows up twice. The rules, and what a second subscription to the same address may and may not overwrite, are in `docs/technical/feed-identity.md`.
- **An import tolerates a broken file, never a broken result** : an exported OPML routinely holds a bare ampersand, a control character or a lying encoding declaration, and the reader cannot fix any of it, so the parser repairs and retries. A single unusable line is reported and skipped, never fatal. What cannot be understood is never guessed at.
- **Stream and library are different things** : the stream is purged by age and volume, the library never is. Promotion freezes and copies the content, which is what lets a library item survive its source disappearing. Never make a library feature read through to a stream row.
- **The CloudKit record budget is a design constraint**, not a detail : around three thousand records total, read states compacted into one record per feed and per month, and never one record per article. Merging is a union, so it stays commutative and idempotent and needs no conflict resolution.
- **Concurrency** : the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so types are main-actor isolated unless marked `nonisolated`. Store types, records, parsers and networking types are `nonisolated` ; database access goes through GRDB's own `DatabaseQueue` / `DatabasePool` serialization rather than a hand-rolled actor.
- **The query language is parsed into a tree**, never built by string concatenation, and the tree is what compiles to SQL or FTS5 with bound parameters.
- **Every long task is resumable** : idempotent batches, a persisted resume point, automatic resumption at the next launch. `BGContinuedProcessingTask` is not reliable enough to assume a task that started will finish.
- **Foundation Models is a feature flag** : the no-LLM path always exists, is always reachable, and is tested. Nothing in the nominal flow may depend on Apple Intelligence being available.
- **Secrets never leave the keychain** : feed credentials and secret feed URLs are stored through the keychain with the appropriate protection class. Never write one to `UserDefaults`, a log line, an error message, a database column or a default export.
- **Be polite to publishers** : conditional requests on every fetch, a token bucket per host, `Retry-After` honoured, an identifying user agent, and a per-device stagger. A change that increases outgoing traffic needs a reason.

## Development Guidelines

- **English in code** : all code is English : variable, constant, function, type names, comments and doc comments. French appears only in translated user-facing strings.
- **Systematic French translations** : every user-facing string must be localizable (`Text("...")`, `String(localized:)`, `LocalizedStringResource`) and must have a French translation in `Flong/Localizable.xcstrings`. Never leave a string untranslated, and never hardcode a user-visible literal outside the catalog. `Text(verbatim:)` is only for content that must not be translated, such as a URL placeholder.
- **Every source file carries the MPL notice** : a new Swift file starts with the Xcode header, followed by the Mozilla Public License 2.0 source notice (Exhibit A of `LICENSE`). MPL copyleft is file-based, so a file without the notice leaves its licensing ambiguous.
- **No em dash character** : never use the em dash character (U+2014) in code, strings or display text. Use ` : ` or ` - ` instead.
- **UI quality in both appearances** : every screen must render correctly in light and dark mode. Rendered article HTML must follow the system appearance too, through `color-scheme` and `prefers-color-scheme`.
- **Every platform is a first-class target** : a change must work on iPhone, iPad and Mac. Guard platform-specific API with `#if os(iOS)` / `#if os(macOS)` rather than dropping a platform, and check that the split view still behaves once collapsed on iPhone. No feature may exist on macOS alone.
- **Accessibility** : support Dynamic Type, give icon-only controls an accessibility label, and keep contrast usable in both appearances.
- **Fix security issues autonomously** : when a security problem is identified (secret exposure, a secret in a log, injection into rendered HTML, an unvalidated URL, a missing keychain protection), fix it without asking for confirmation as long as the fix introduces no regression, and record it under a `### Security` entry in `CHANGELOG.md`.
- **Never commit a real feed URL carrying a secret, a username, a password or a token**, in code, tests, fixtures or documentation. Test fixtures use `https://feeds.example.com` and obviously fake credentials.
- **Branch workflow** : all commits go on a branch, never directly on `main`. The only exceptions are the initial repository bootstrap and the release version bump, whose CHANGELOG promotion commit goes on `main` with the exact message ``Bump version `vX.Y.Z` ``.
- **One session = one branch, always** : all the work done in a single session lives on one and the same branch. Create it at the first commit and keep committing to it for every later change in the session, even when a later request is unrelated to the first. Never open a second branch or split a session's work across branches or PRs. The one exception is a session that outlives its own pull request : once the branch is merged, the next unit of work starts a new branch off `main`, since a merged commit is never rewritten.
- **Push as you go** : push the session branch to `origin` after each commit (`git push -u origin <branch>` the first time), so the work is never only local. Do not batch pushes to the end of a session. This is about pushing often, not committing often : keep committing whole, coherent, verified units of work, and never split one into a trail of small tentative commits ("wip", "fix typo", "try again"). If a change is not yet coherent or does not build, finish it before committing.
- **Fix a bad commit by rewriting it, never by adding a correction commit** : when a commit turns out to contain botched or incomplete work, amend or rebase it so history shows the work as it should have been done (`git commit --amend`, or `git rebase -i` for an older commit on the session branch). Since the branch is pushed after every commit, rewriting means re-pushing with `git push --force-with-lease`, never a bare `--force`. This applies only to the session's own branch : never rewrite `main`, never rewrite a merged commit, and stop rewriting once someone has started reviewing the PR.
- **Git author** : all commits must be authored as `Claude <noreply@anthropic.com>`. Use `git commit --author="Claude <noreply@anthropic.com>"` for every commit.
- **Commit messages in English**, regardless of the conversation language.
- **English for written deliverables** : GitHub issues, pull request titles and descriptions, and any specification or design document are written in English, regardless of the conversation language. French remains only for translated UI strings.
- **A change must build and lint before it is committed** : `swift-format lint --strict` clean, and the iOS and macOS builds passing. Do not commit a state you have not built.
- **Always use the GitHub templates** : every issue must be filed through a form in `.github/ISSUE_TEMPLATE/`, and every pull request must use `.github/PULL_REQUEST_TEMPLATE.md` : fill the Summary, Related issue and Changes sections, and tick every applicable checklist item. When creating a PR with the `gh` CLI, build the body from the template, since `gh` does not apply it automatically.
- **PR progress tracking** : for any work tracked by a PR carrying a checklist, comment the progress on the PR at each commit (what changed, why, which checklist items it covers, verification status) and tick the matching checklist items in the PR body as they are completed.
- **GitHub release on every version tag** : after pushing a version tag, create the matching GitHub Release : `gh release create vX.Y.Z --title "vX.Y.Z"` with that version's CHANGELOG section as the notes, ending with the comparison link (`https://github.com/frousselet/Flong/compare/vPREV...vX.Y.Z`).
- **Keep README.md up to date** : after any change that adds, removes or modifies a feature, a dependency, a supported platform or a build instruction, update `README.md` accordingly. It is the public-facing documentation and must always reflect the current state of the codebase.
- **Keep CHANGELOG.md up to date** : before committing and before tagging, update `CHANGELOG.md` following the [Keep a Changelog](https://keepachangelog.com/) format. Add entries under `## [Unreleased]` with the right category (Added, Changed, Fixed, Removed, Security). When tagging, move them under a new `## [x.y.z] - YYYY-MM-DD` heading and add the comparison link at the bottom.
- **CHANGELOG entries are terse and non-redundant** (strict) : (1) one line maximum per entry, a single sentence, no multi-paragraph explanations and no exhaustive lists of files or internals, that detail lives in the git history and the PR; (2) each category appears at most once per release, never repeated blocks; (3) never log a Changed or Fixed entry about something Added in the same release, fold that detail into the Added entry instead.
- **Documentation lives in `docs/`** : the specification at `docs/specification.md`, technical references under `docs/technical/`, one file per subject. A change that alters a documented behaviour updates its page in the same commit.
- **Persistent instructions** : when the user asks to "always do something" or to "remember something", add it to this `CLAUDE.md` file so it persists across sessions.
