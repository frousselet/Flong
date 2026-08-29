# Feed identity and subscriptions

A feed is identified by its URL, and that column is unique. Two spellings of one address therefore have to collapse into a single row before they reach the store, otherwise a re-import silently doubles the subscription list and the reader sees every article twice.

This page records the rules. Everything that creates a subscription follows them : the OPML import, the share extension, a pasted address, a discovered `<link rel="alternate">`.

## Canonical URL

`FeedURL.canonical(_:)` is the only way in. It is deliberately conservative : it normalizes what carries no meaning and leaves alone what does.

### Normalized

| Input | Canonical form | Why |
| ----- | -------------- | --- |
| `feeds.example.com/atom.xml` | `https://feeds.example.com/atom.xml` | A scheme is assumed when the address has none. |
| `feed://feeds.example.com/atom.xml` | `https://feeds.example.com/atom.xml` | `feed:` and `feed://` come from browsers and OPML files, and no server answers on them. |
| `HTTPS://Feeds.Example.COM/Atom.xml` | `https://feeds.example.com/Atom.xml` | Scheme and host are case insensitive. The path is not. |
| `https://feeds.example.com.:443/atom.xml` | `https://feeds.example.com/atom.xml` | A trailing dot on the host and a default port name the same server. |
| `https://feeds.example.com` | `https://feeds.example.com/` | An empty path is the root. |
| `https://feeds.example.com/atom.xml#recent` | `https://feeds.example.com/atom.xml` | A fragment never reaches the server. |
| `https://feeds.example.com/atom.xml?` | `https://feeds.example.com/atom.xml` | An empty query is no query. |

Surrounding whitespace is trimmed first.

### Left alone

- **The scheme.** `http` and `https` stay distinct. Upgrading silently would merge two rows that can serve different content, and would break a feed only published over `http`.
- **The query string.** `?format=rss` selects the feed on plenty of sites. Parameters keep their order.
- **The trailing slash.** `/feed` and `/feed/` are different resources on plenty of servers.

### Refused

| Address | Error |
| ------- | ----- |
| An empty string | `empty` |
| Anything `URLComponents` cannot read, or with no host | `malformed` |
| A scheme other than `http` or `https` | `unsupportedScheme` |
| An address carrying a user name or a password | `embeddedCredentials` |

Credentials in the URL are refused rather than stored : the row would hold a password in clear, and section 9 of the specification keeps every secret in the keychain. Private feeds get their own path when that section is implemented.

## Folders

A folder is a view over a root tag, so its path is written the way a tag is : components separated by a slash, `Tech/iOS`. `FolderPath.normalized(_:)` trims each component and drops the empty ones, so `/Tech//iOS/` and `Tech / iOS` both settle on `Tech/iOS`. A path holding nothing means no folder.

A folder holds nothing of its own : it exists only as long as a feed carries its path.

- `folders()` returns the stored paths **and their ancestors**, because a feed filed in `Tech/iOS` implies a `Tech` level the sidebar has to draw. `feedCount` stays the direct count, so a synthesized ancestor reports zero.
- Renaming a folder carries its subfolders along : `Tech` renamed to `Veille` moves `Tech/iOS` to `Veille/iOS`, since a path that no longer starts the same way would leave its children orphaned.
- Removing a folder never removes a feed. What sat directly in it moves outside every folder, and a subfolder floats up one level with its feeds.

## Subscribing twice

Subscribing to an address already followed is not an error : it returns the feed already there, with `isNew` false.

**What the reader did outranks what an import carries.** A title they changed and a folder they moved the feed to are never overwritten. Only a field still empty is filled in, which lets a second import complete a feed with the site URL or the icon the first one lacked.

A feed with no title of its own is called after its host, `www.` stripped, until the feed states one.

That is the only moment a refresh may rename a feed : while the stored title is still that host fallback. A title carried by an OPML file is already somebody's choice, and a rename certainly is, so neither is ever overwritten by what a publisher decides to call themselves next month.

## Ordering

Feeds are listed through the `localizedStandardCompare` collation, in SQLite, so `Écrans` files under E rather than after Z. Folders are sorted the same way, in Swift, since the list is small and built by aggregation.
