# From a feed to the store

Refreshing one feed is where the four modules meet : the fetcher brings bytes, the parser turns them into articles, the sanitizer decides what of an article may be kept, and the store recognizes what it has already seen. All of it lands in one transaction, so a feed is either updated whole or not at all.

## Recognizing an article

An article is matched on its identity, the GUID or the link and date of `docs/technical/feed-formats.md`, within its feed. That is what makes a refresh idempotent : the same feed served twice adds nothing the second time.

**An update rewrites the article, never what the reader did to it.** Title, body, excerpt, author, dates and enclosures are refreshed from the feed ; read and starred stay exactly as they were. A publisher fixing a typo must not resurrect an article somebody read last week.

## What a feed may decide about itself

| Field | Rule |
| ----- | ---- |
| title | Only while the stored title is still the host fallback. An OPML title is already somebody's choice, and a rename certainly is. |
| site address, icon, language | Filled in while empty, never overwritten. |
| `ETag`, `Last-Modified` | Always taken from the last answer. |
| observed interval | Recomputed from the dates the feed just served, which is the only history certain to be complete. |

## Health

Every attempt is counted, successful or not, which is what makes the 304 rate meaningful. A success clears the failure count and the quarantine ; a failure adds to it and records a short reason. The reason is a code, never an address : the address of a private feed is a secret, and a failure message is exactly the sort of place it leaks from.

Quarantine comes after three failures when the answer is a decision, 401, 403, 404 or 410, and after six when it might be an outage. A quarantined feed is not asked for at all, by a scheduled refresh or by a pull, until the reader does something about it.

## Bodies

The body is the content when the feed serves one, the summary otherwise, sanitized against the article's own address so its relative links keep working. The excerpt shown in a list comes from the summary first, since that is what the publisher wrote for the purpose, and from the body only when there is no summary.

An article with no body at all is stored anyway : its title, its date and its link are still worth having, and the reader mode of M2 will be able to go and fetch the rest.

## Retention

The stream is a cache. It is purged by age and by volume, and that is the mechanism that bounds disk usage.

- **By age**, with a default of thirty days.
- **By volume**, against the real size of the store, `page_count` times `page_size`. Articles go oldest first, in batches, and the file is rewritten afterwards, since deleted rows leave their pages behind and the file would otherwise never shrink.
- **What the reader marked is never purged.** Starred, written on, or filed in a collection : the three are one condition, and a purge that spared only the stars would take the article somebody wrote three paragraphs on.

## Refreshing many feeds

Six feeds are fetched at once. The throttle of `docs/technical/fetching.md` already spaces out one host ; this bound is about the work in flight, which is what keeps memory flat on a phone refreshing a thousand feeds.

## The picture that stands for an article

Publishers state it in five places and agree on none of them, so the answer is a documented order rather than a guess :

1. **What the feed says the article's picture is** : `media:thumbnail`, a `media:content` that is an image, `itunes:image`, JSON Feed's `image` or `banner_image`, an `u-photo` that is not inside an `h-card`. A statement about the article beats anything inferred from it.
2. **An attached image**, for a feed that encloses one rather than naming it. The stated type decides ; half of them state none, and the address is then all there is to go on.
3. **The first picture in the body**, which is what a reader would call the article's picture if asked.

Every one of them is resolved against where it was found and vetted before it is kept : a feed states an address relatively as often as absolutely, and a relative one handed to the network comes back as `unsupported URL` in the reader's console with a path and nothing to act on. That is not an error worth reporting, it is an address that should never have been asked for. `HTTPURL` is the one place that judges, and `ImageStore` checks again at the boundary itself, so a hole upstream is a picture that does not appear rather than an error in a log.

The body is read **after** sanitizing, never before : the sanitizer has already resolved every address against the article, vetted its scheme and thrown out the tracking pixels, so what is left is both absolute and safe to ask for. A picture the publisher itself declares smaller than sixty four points on its longest side is furniture, a share button or a rating star, and is skipped. Only stated dimensions are read : asking the network how big a picture is before deciding whether to show it would mean fetching every image of every article, which is exactly the traffic a reader owes it to publishers not to generate.

**A thumbnail is not an enclosure.** It used to be counted as one, which put a media badge on every article of a feed that merely illustrates its headlines. `media:thumbnail` and `itunes:image` are statements about the article ; `enclosure` and `media:content` are files attached to it, and only those make an article carry media.

Only the address is stored, never the file. It travels with the article, so a picture can go dead on the publisher's side while the text stays : that is the deal, and it is why the text travels and the picture does not.

A publisher who illustrates an article after publishing it is improving it, so a refresh takes the new picture ; one who drops it has usually just reworded the feed, and the picture already shown stays.

## The same article twice

A paper that publishes a feed per desk puts the same piece in several of them, and a reader following two desks was reading it twice : the same headline three minutes apart, filed under one story that then claimed three articles when it had two.

Two articles are the same article when their **canonical key** matches. The key is the address, reduced to what identifies the page : the host without its `www`, the path without a trailing slash, and what is left of the query once the tracking parameters are gone, in a fixed order. The fragment goes, since `#comments` is a place on a page rather than another page. A parameter that says *what* to read is kept : `?p=1234` is where the article is, `?utm_source` is who sent the reader.

Where a feed gives no address at all, the key is the headline, folded to its letters, **scoped to the newsroom and to the day**. That scope is not a detail : two papers covering one event write two articles, and collapsing those would destroy the one thing the digest is for, which is that several rooms saying the same thing is the story.

The second copy **keeps its row** and points at the first. It belongs to a feed the reader follows, and unsubscribing from that feed must take its own article away rather than someone else's. It is shown nowhere : not in a list, not in a count of unread, not in the stories, not in the tail. `ON DELETE SET NULL` on the pointer means that when the first copy is purged by age, the second stops being a duplicate of anything and becomes the article.

A duplicate is found **wherever it is**, this feed included. A feed whose builder gives its articles a fresh identifier every time hands the same piece over again and again, and the identifier is exactly what stops the ordinary path from noticing ; the key notices. A third copy points at the original rather than at the second.

The key arrived as an empty column, so only articles fetched after it existed had one, and a reader who had been running Flong for a week kept every copy they already had. `v13` keys the whole stream once and marks the copies : the earliest of each key is the article and the rest point at it. One pass, a second on a large stream, and never again, which is cheaper than the machinery of a resumable job for something that runs once.
