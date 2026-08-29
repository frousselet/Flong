# Fetching feeds

Every device collects for itself. There is no server in front of the publishers, so Flong is the client they see in their logs, and it behaves accordingly.

## Conditional, always

Every request carries `If-None-Match` and `If-Modified-Since` when the store knows an `ETag` or a `Last-Modified`. A feed that has not changed then costs a 304 and a few hundred bytes instead of a download, which is the single largest saving available to a reader following a thousand feeds.

The rate of 304 answers is kept per feed, `not_modified_count` over `fetch_count`, and surfaced as a health indicator : a feed that never answers 304 is one that will cost its full weight on every refresh for ever.

`Accept-Encoding` is deliberately not set. `URLSession` asks for gzip and brotli by itself and decodes them before handing anything over ; setting the header here would only turn that off.

## Politeness

- **One bucket per host name, not per feed.** A reader following forty feeds on one platform would otherwise hit it forty times at once, which is indistinguishable from an attack and gets the application blocked rather than the feeds refreshed.
- **Credit up to a burst, and no further.** The reservation runs on a clock allowed to lag behind the real one by exactly one burst, so a host left alone can be asked several things at once, and a reader who was away for a week still cannot come back with a thousand simultaneous requests.
- **`Retry-After` is honoured**, as a number of seconds or as a date. It holds every request to that host, not only the one that was refused. This is the difference between a client a publisher tolerates and one they block.
- **Backoff doubles with jitter.** A thousand readers who all failed during one outage must not come back in the same second.
- **The user agent names the project and carries its address**, so a publisher looking at their logs can tell what is asking and why.
- **Nothing sleeps inside the throttle.** It hands out a moment and the caller waits for it, so one slow host never holds up the others.

## Limits

| Limit | Value | Why |
| ----- | ----- | --- |
| request timeout | 15 s | A feed that takes longer is not worth the wait on a phone. |
| resource timeout | 60 s | The whole exchange, redirects included. |
| body | 8 MB | Feeds are text. A body past this is a mistake or a trap, and it is refused while it streams rather than after it lands. |

Cookies are refused outright, and the URL cache is bypassed : the store already holds the conditional state, and a second cache in front of it would only answer with what it already knows.

## When a feed is asked again

The interval comes from the feed's own history : the **median** gap between publications, never the mean, since one burst of ten posts in an afternoon would otherwise convince the reader that the feed publishes every four minutes for ever. It is bounded between fifteen minutes and twenty four hours, and a per-feed setting outranks it.

A pseudo-random stagger, derived from the feed and from a stable identifier for the installation, keeps a reader's several devices from asking together. Without it they multiply the traffic reaching a publisher by the number of devices on the account, for no benefit at all.

## What a failure means

| Answer | Treatment |
| ------ | --------- |
| 304 | Nothing changed. Counted as health, not as a failure. |
| 401, 403 | The feed needs credentials or refuses these. Quarantined after three, per section 9, so dead credentials are not hammered at the publisher. |
| 404, 410 | Gone. Quarantined, with the reader told. |
| 429, 503 | The server asked to be left alone. The whole host is paused. |
| anything else | Counted, and retried with backoff until the quarantine threshold. |

A quarantined feed is not asked for at all until the reader does something about it.

## Not here yet

The network settings of section 8, Wi-Fi only, suspension in Low Power Mode and the monthly cellular cap, arrive with the settings screen. Background refresh arrives with M4 ; until then, refreshing happens on returning to the foreground and on a pull, which section 25 names as the primary mechanism anyway.

## Pictures

The pictures articles carry are asked for from the publisher too, and the same politeness applies : the identifying user agent of this page, a body cap, and a disk cache so a picture already seen is never asked for twice. They are fetched when a screen actually shows one, never in advance and never in a batch : a reader who does not scroll to an article costs its publisher nothing.

Nothing is asked for that the feed did not already point at. The rendered article has always loaded its own images, so this adds no new kind of outgoing request, only the same kind on the list.
