# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flong is a native FreshRSS client for iOS, iPadOS and macOS, written in Swift 6 with SwiftUI and SwiftData. It talks to a FreshRSS instance through the Google Reader compatible API exposed at `/api/greader.php`.

FreshRSS is the first and only backend today. Other services (Miniflux, Inoreader, The Old Reader and anything else speaking the same API) are expected later, so backend access must always sit behind a provider abstraction rather than being called directly from the UI.

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

### Signing

The app carries a `keychain-access-groups` entitlement (`Config/Flong.entitlements`), which the credential store needs. That entitlement requires a provisioning profile, so a machine building it for the first time has to let Xcode create one and register itself :

```bash
xcodebuild build -project Flong.xcodeproj -scheme Flong -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Without `-allowProvisioningDeviceRegistration` the build fails with *Device ... isn't registered in your developer account*. Once the profile exists, ordinary builds work again. Only macOS needs this : iOS gets its application identifier from its own profile, and the simulator needs none.

### Testing

```bash
xcodebuild test -project Flong.xcodeproj -scheme Flong \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skip-testing:FlongUITests
xcodebuild test -project Flong.xcodeproj -scheme Flong \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FlongTests/GReaderClientTests
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

The app target uses an Xcode synchronized file group, so a new file placed in `Flong/` joins the target with no `project.pbxproj` edit. Directories carry the architecture :

| Directory | Contents |
| --------- | -------- |
| `Flong/App/` | App entry point, root view, and the observable session object the UI reads |
| `Flong/Core/Accounts/` | Account model, keychain wrapper, secret storage abstraction |
| `Flong/Core/Feeds/` | `FeedProvider` protocol and the backend-neutral value types it exchanges |
| `Flong/Core/Feeds/GReader/` | GReader implementation : HTTP client, DTOs, errors, stream identifiers, provider |
| `Flong/Data/` | SwiftData models and the sync engine that writes remote payloads into the store |
| `Flong/Features/` | One directory per screen area, each holding its views |
| `Flong/Support/` | Logging and cross-cutting helpers |
| `FlongTests/` | Swift Testing unit tests |
| `FlongUITests/` | XCUITest suites |

### Key patterns

- **Provider abstraction is mandatory** : every backend call goes through the `FeedProvider` protocol. Views and the session object must never reference `GReader` types directly, otherwise adding a second service means rewriting the UI.
- **Concurrency** : the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so types are main-actor isolated unless marked `nonisolated`. Networking types, DTOs and SwiftData models are declared `nonisolated`; the HTTP client is an `actor`; background store writes go through a `@ModelActor`.
- **SwiftData models never use `id` as a stored property**, because `PersistentModel` already provides one. The remote identifier is `remoteID`, and relationships are mirrored by a stored foreign key (for example `Article.feedID`) so `@Query` predicates filter on an indexed column instead of walking a relationship.
- **Optimistic local writes** : read and star actions update the local store first, then push to the server, and roll the local change back if the server refuses it. The interface must never wait on the network to reflect a tap.
- **Credentials are shared across the account's devices** : they live in the keychain with `kSecAttrSynchronizable`, which hands the item to iCloud Keychain, and `kSecUseDataProtectionKeychain`, which is what selects the modern keychain on macOS. Without the second, macOS silently uses its legacy file-based keychain, which never syncs. Every `SecItem` call for one item must carry the same flags : a query that omits `kSecAttrSynchronizable` only matches non-synchronizable items. A synchronizable item cannot use a `ThisDeviceOnly` protection class. The session token is deliberately not synced : it is a per-device cache rebuildable from the credentials.
- **Credentials never leave the keychain** : the FreshRSS API password and the session token are stored through `SecretStore`. Never write them to `UserDefaults`, a log line, or a file.

## Development Guidelines

- **English in code** : all code is English : variable, constant, function, type names, comments and doc comments. French appears only in translated user-facing strings.
- **Systematic French translations** : every user-facing string must be localizable (`Text("...")`, `String(localized:)`, `LocalizedStringResource`) and must have a French translation in `Flong/Localizable.xcstrings`. Never leave a string untranslated, and never hardcode a user-visible literal outside the catalog. `Text(verbatim:)` is only for content that must not be translated, such as a URL placeholder.
- **Every source file carries the MPL notice** : a new Swift file starts with the Xcode header, followed by the Mozilla Public License 2.0 source notice (Exhibit A of `LICENSE`). MPL copyleft is file-based, so a file without the notice leaves its licensing ambiguous.
- **No em dash character** : never use the em dash character (U+2014) in code, strings or display text. Use ` : ` or ` - ` instead.
- **UI quality in both appearances** : every screen must render correctly in light and dark mode. Rendered article HTML must follow the system appearance too, through `color-scheme` and `prefers-color-scheme`.
- **Every platform is a first-class target** : a change must work on iPhone, iPad and Mac. Guard platform-specific API with `#if os(iOS)` / `#if os(macOS)` rather than dropping a platform, and check that the split view still behaves once collapsed on iPhone.
- **Accessibility** : support Dynamic Type, give icon-only controls an accessibility label, and keep contrast usable in both appearances.
- **Fix security issues autonomously** : when a security problem is identified (credential exposure, a secret in a log, injection into rendered HTML, an unvalidated URL, a missing keychain protection), fix it without asking for confirmation as long as the fix introduces no regression, and record it under a `### Security` entry in `CHANGELOG.md`.
- **Never commit a real instance URL, username, password or token**, in code, tests, fixtures or documentation. Test fixtures use `https://rss.example.com` and obviously fake credentials.
- **Branch workflow** : all commits go on a branch, never directly on `main`. The only exceptions are the initial repository bootstrap and the release version bump, whose CHANGELOG promotion commit goes on `main` with the exact message ``Bump version `vX.Y.Z` ``.
- **One session = one branch, always** : all the work done in a single session lives on one and the same branch. Create it at the first commit and keep committing to it for every later change in the session, even when a later request is unrelated to the first. Never open a second branch or split a session's work across branches or PRs.
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
- **Documentation lives in `docs/`** : technical references under `docs/technical/`, one file per subject. A change that alters a documented behaviour updates its page in the same commit.
- **Persistent instructions** : when the user asks to "always do something" or to "remember something", add it to this `CLAUDE.md` file so it persists across sessions.
