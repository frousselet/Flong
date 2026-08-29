# OPML import

An OPML file is how a reader leaves the service they were on. Flong reads one, follows what it holds, and keeps the folder tree it describes. It is a one-shot operation : nothing links Flong to where the file came from.

## What is read

| Attribute | Used as | Note |
| --------- | ------- | ---- |
| `xmlUrl` | the feed address | The only attribute that makes an outline a feed. |
| `title`, `text` | the title | `title` wins. OPML 2.0 requires `text`, and exporters fill both as often as not. |
| `htmlUrl` | the site address | Canonicalized, and dropped rather than fought over when it makes no sense. |
| `category` | the folder | Only for a feed no outline nests. See below. |
| `type` | nothing | |

Attribute names are matched without regard to case : `xmlUrl`, `xmlurl` and `XMLURL` all appear in files that are otherwise valid.

`type` is deliberately ignored. Exporters write `type="rss"` on Atom feeds, `type="link"` on ordinary feeds, or leave it out, so it carries no information. An outline is a feed when it has an address, and a folder when it has children.

## Folders

Nesting is the folder tree : an outline without an address contributes its title as a path component, so a feed two levels down lands in `Tech/iOS`.

A flat file gets a second chance through `category`, which OPML 2.0 defines as a comma separated list of slash delimited paths. The first path is used, normalized like any folder. Nesting always wins : `category` only fills in for a feed no outline holds.

## Tolerance

Section 19 of the specification asks for tolerance towards malformed files, and exported OPML is routinely malformed. A file `XMLParser` refuses is repaired once and parsed again, rather than being handed back as a failure.

The repair pass does four things, and nothing else :

1. **Decodes what the declaration got wrong.** UTF-8 first, Latin-1 second, lossy UTF-8 last. The XML declaration is then dropped, since the text is handed on as UTF-8 and a declaration naming another encoding would send the parser looking for bytes that are no longer there.
2. **Removes the characters XML forbids**, the control characters other than tab, newline and carriage return.
3. **Escapes a bare `&`.** `Cook & Book` is what a title looks like in a good half of the files out there, and it makes the whole document unparseable.
4. **Escapes an entity XML does not know.** XML declares five named entities and nothing else, so `&eacute;`, which HTML exporters write freely, is as fatal as a bare ampersand. It is escaped too, and shows up as itself in the title. Losing a thousand feeds over one accent would be the worse trade.

A file that is still unreadable, or that parses but holds no `opml` element, stops the import. Nothing else does.

## The report

A single unusable line never stops an import : a file of a thousand feeds routinely holds two addresses nobody can make sense of. They are collected in the report instead, with the reason `FeedURL` gave, and the reader decides whether to care.

```
added            feeds now followed
alreadyFollowed  feeds Flong already had, whatever the file called them
skipped          lines that carry no usable address, with their reason
```

An address carrying a password lands in `skipped`, since section 9 of the specification keeps every secret in the keychain and the row would hold it in clear.

## Twice over

Importing the same file twice adds nothing : addresses are canonicalized before they are matched, so `feed://Example.com/rss` and `https://example.com:443/rss` are the same subscription, inside one file and between two imports.

A second import never overwrites a title the reader changed or a folder they moved a feed to. It only fills in what is still empty, as `docs/technical/feed-identity.md` sets out.

## What is not there yet

Export, and the redacted mode section 9 requires, arrive with M7. So does the import from a service API, which reuses this store but not this parser.
