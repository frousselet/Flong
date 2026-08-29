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
- **What the reader kept is never purged.** A starred article survives, and so will a library item once M2 introduces one.

## Refreshing many feeds

Six feeds are fetched at once. The throttle of `docs/technical/fetching.md` already spaces out one host ; this bound is about the work in flight, which is what keeps memory flat on a phone refreshing a thousand feeds.

## The picture that stands for an article

Publishers state it in five places and agree on none of them, so the answer is a documented order rather than a guess :

1. **What the feed says the article's picture is** : `media:thumbnail`, a `media:content` that is an image, `itunes:image`, JSON Feed's `image` or `banner_image`, an `u-photo` that is not inside an `h-card`. A statement about the article beats anything inferred from it.
2. **An attached image**, for a feed that encloses one rather than naming it. The stated type decides ; half of them state none, and the address is then all there is to go on.
3. **The first picture in the body**, which is what a reader would call the article's picture if asked.

The body is read **after** sanitizing, never before : the sanitizer has already resolved every address against the article, vetted its scheme and thrown out the tracking pixels, so what is left is both absolute and safe to ask for. A picture the publisher itself declares smaller than sixty four points on its longest side is furniture, a share button or a rating star, and is skipped. Only stated dimensions are read : asking the network how big a picture is before deciding whether to show it would mean fetching every image of every article, which is exactly the traffic a reader owes it to publishers not to generate.

**A thumbnail is not an enclosure.** It used to be counted as one, which put a media badge on every article of a feed that merely illustrates its headlines. `media:thumbnail` and `itunes:image` are statements about the article ; `enclosure` and `media:content` are files attached to it, and only those make an article carry media.

Only the address is stored, never the file. It travels to the library with the rest of a kept article, so a picture can go dead on the publisher's side while the text stays : that is the deal, and it is why the text is copied and the picture is not.

A publisher who illustrates an article after publishing it is improving it, so a refresh takes the new picture ; one who drops it has usually just reworded the feed, and the picture already shown stays.
