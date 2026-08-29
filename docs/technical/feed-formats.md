# Feed formats

Flong reads RSS 0.9x, RSS 1.0 over RDF, RSS 2.0, Atom 1.0, JSON Feed 1.0 and 1.1, and h-feed microformats2. All of it lands in one normalized shape, `ParsedFeed`, so nothing downstream ever asks which format an article came from.

## Choosing a parser

The declared content type is a hint and nothing more : servers send RSS as `text/plain`, JSON Feed as `text/html`, and Atom as anything at all. What the bytes start with decides the order, and every format is tried before a document is declared not to be a feed.

The distinction matters for the answer given back : `notAFeed` means one parser understood the bytes and found no feed in them, `unreadable` means none of them could read the bytes at all. A page that is only a web page gets the first ; a truncated download gets the second.

## RSS and Atom share one parser

They differ in their element names and in almost nothing else, and a real feed mixes them freely : an Atom link inside an RSS channel, a Dublin Core date inside an Atom entry, a `content:encoded` carrying the body RSS has no element for. Matching on the local name **and the namespace**, rather than on a declared format, is what makes all of that readable.

| Field | RSS | Atom |
| ----- | --- | ---- |
| body | `content:encoded`, else `description` | `content`, else `summary` |
| address | `link`, or a permalink `guid` | `link rel="alternate"` |
| identity | `guid` | `id` |
| date | `pubDate`, `dc:date` | `published`, else `updated` |
| author | `dc:creator`, `author` | `author/name` |
| media | `enclosure`, `media:content` | `link rel="enclosure"` |

Three things are worth knowing about the implementation :

- **CDATA never reaches `foundCharacters`.** Most RSS bodies live in a CDATA section, and a parser that only implements the characters callback silently returns empty descriptions.
- **An Atom `content type="xhtml"` is markup, not text.** Its children are rebuilt into a string as they are walked.
- **A permalink `guid` doubles as the address**, which is how plenty of feeds spell a link they never wrote down. An Atom `id` never does : it is a URN as often as not.

## Identity

An article is identified by its GUID, and failing that by its link paired with its publication date, as section 4 of the specification states. An article offering neither is dropped rather than stored : it cannot be recognized on the next refresh, so it would come back as new for ever.

## Dates

The specifications name RFC 822 for RSS and RFC 3339 for Atom, and publishers write neither faithfully : missing seconds, a two digit year, a named zone nobody agrees on, a space where the `T` belongs. Each spelling is tried in turn, always with a fixed English locale, since a French device must still read `Wed, 27 Aug 2026`. A date that means nothing is left empty rather than guessed at, because a wrong date sorts an article into the wrong week for good.

## Bodies

Parsers hand over the markup the publisher served, untouched. Sanitizing happens on the way into the store, where the article address is known and can resolve the relative links a feed serves. Plain text bodies, from JSON Feed or an Atom `type="text"`, are escaped so they render as the author typed them.

## Broken feeds

A document `XMLParser` refuses goes through `XMLRepair` and is parsed again, the same pass the OPML import uses : the encoding a declaration gets wrong, the control characters XML forbids, the bare ampersand, the HTML entity XML does not know.

A feed cut off halfway keeps the articles it got through. Half a refresh beats none, and the rest arrives on the next one.

The corpus behind all of this lives in `FlongTests/Fixtures/Feeds`, and grows with every feed found broken in a new way.

## Discovery

A reader pastes the address of a site, not of its feed. `FeedDiscovery` reads what the page declares in `<link rel="alternate">`, and when it declares nothing, the usual locations are worth trying, in order. Guessing is a fallback, never the first request.
