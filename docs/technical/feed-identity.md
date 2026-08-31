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

## Groups of sources

**A feed belongs to the publisher serving it, and belongs to it by arithmetic rather than by filing.** `Feed.domain` is the host of the site, or of the feed itself where the site is unknown : `FeedURL.room(of:)` in both cases, so a group and a newsroom on the front page are one notion computed once. The host is lowercased and stripped of its `www`, and it is not reduced to a registrable domain ; `feed-identity` and `digest` agree on that, and the reason is the same in both places.

- A paper publishing a feed per desk is **one group**. `lemonde.fr/rss/une.xml` and `lemonde.fr/rss/sport.xml` sit together, and so does a feed served from a third party whose `htmlUrl` names the paper's own site.
- `blog.example.com` is **its own group**, not part of `example.com`. Folding the two would need the public suffix list and would put a paper and its unrelated blog under one heading.
- Nothing is stored. `SubscriptionStore.groups(of:named:)` is a grouping over the feeds, so there is no group to create, no group to keep in step with a subscription arriving or going, and no empty group left behind.

### The name over a group

The one thing that cannot be worked out is that `lemonde.fr` is called `Le Monde`, and it is the whole of the `source_name` table : one row per publisher the reader actually named, keyed by the domain, unique on it.

- The **domain is the key** and the name is only shown. A reader who renames a group has renamed a heading in their list, not moved a feed anywhere, and the selection survives the renaming.
- An empty name, a blank one, or the address written out again is **not a name** : the row goes and the group is called what it is. That is what lets a reader undo a naming without having to remember the address.
- Groups sort by the name they are shown under, in the reader's own locale, so a renamed one files under its name rather than under its host.

## Folders

*Removed.* A feed carried the path of a folder it sat in, and nothing in Flong ever let a reader make one, rename one or take one away : every folder that existed came out of an imported OPML file, so the column held somebody else's filing, inherited and untendable. Migration `v23.publishersRatherThanFolders` drops it. `tag:` no longer answers for a feed either, since the folder was the one thing about a feed a tag could match ; `feed:` and `site:` are what narrow a search to where an article came from.

## Subscribing twice

Subscribing to an address already followed is not an error : it returns the feed already there, with `isNew` false.

**What the reader did outranks what an import carries.** A title they changed, a source they made a favourite and a name they wrote over a publisher are never overwritten. Only a field still empty is filled in, which lets a second import complete a feed with the site URL or the icon the first one lacked.

That rule is right for an import and wrong for what arrives from iCloud, and `SyncPayload` is the one place that says so : a favourite set on another device is the later word on the matter, so it is applied over the upsert rather than through it. A record written before favourites existed carries no such field, and nothing said is not the same as `no`.

A feed with no title of its own is called after its host, `www.` stripped, until the feed states one.

That is the only moment a refresh may rename a feed : while the stored title is still that host fallback. A title carried by an OPML file is already somebody's choice, and a rename certainly is, so neither is ever overwritten by what a publisher decides to call themselves next month.

## Ordering

Feeds are listed through the `localizedStandardCompare` collation, in SQLite, so `Écrans` files under E rather than after Z. Groups are sorted the same way, in Swift, since the list is small and built by aggregation.
