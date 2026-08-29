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
