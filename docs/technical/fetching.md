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

## Which feeds a short budget goes to

A background refresh is given about twenty-five seconds and is cancelled when they are up, so the order the due feeds are taken in decides which ones are ever refreshed at all.

They used to be taken in the order the database returned them, which for UUIDv7 keys is the order they were subscribed to. A reader following three hundred feeds whose budget ran out at the eightieth had the next two hundred and twenty never refreshed in the background : the following pass started from the same end and was cut off in the same place. Their oldest subscriptions were always fresh and their newest never were.

They are sorted by how overdue each one is **against its own rhythm**. A daily feed an hour late and an hourly feed an hour late are both an hour late, and only one of them has anything new : measured relatively, the hourly one is a whole interval overdue and the daily one a twenty-fourth of one. A feed nobody has ever fetched is the most overdue thing there is. A feed that has been failing is not made more urgent by failing, its backoff having already pushed its next fetch out, or one broken feed would crowd out three hundred working ones.

## What a background pass will not spend

**Nothing runs in Low Power Mode.** The reader has told the system to stop doing things they did not ask for, and a feed reader waking the radio on its own is exactly such a thing. What they did ask for still works : opening Flong refreshes, and so does a pull on the front page.

**Every refresh may go over a network the reader pays for, the background one included.** It could not, and that was a feature that ate the one behind it. iOS calls every cellular interface expensive, always and not only under Low Data Mode, and `URLSession` refuses a request it may not send rather than falling back : so a background refresh on 5G sent nothing at all, not one feed was asked, the task reported itself a success, and the reader in the street who had asked to be told about new articles was told nothing, every half hour, all day. What a pass costs is already bounded by the deadline it works to and by the conditional request it makes of every feed, which is a few hundred bytes for a feed with nothing new ; refusing the network outright bought very little and cost the whole of the notifications. `FetchRequest.isExpensiveNetworkAllowed` stays, unset by anything today, because it is where the `Wi-Fi only` preference of section 8 will be answered.

A refresh the reader asked for is a different matter, and is allowed whatever network there is. They asked and they are looking at it, and second-guessing them about their own data plan would be the application deciding something that is theirs to decide.

**A request the system would not send is not a failure.** `URLSession` answers a request it may not carry with `networkUnavailableReason` rather than falling back, and no network at all answers the same way. That says something about the device and nothing about the feed, so it is not written down : the fetch counts as skipped, the feed's health is untouched, and it is asked again on the next pass. Counted as failures, as they were, six background passes on a tethered connection quarantined every feed a reader had, for a fault that was never the publisher's and that the reader could not see.

**Asking more often does not buy more grants, but it does stop refusing them.** `BGAppRefreshTask` is granted on the system's own budget, worked out from how often the reader opens the application, and a shorter floor does not raise that budget. What a floor does do is discard any opportunity offered inside it, in a window the system had already decided to give. So it matches the fifteen minutes a feed is held to anyway, and the system's budget is left as the only limiter.

**A pass that ran out of time reports success.** Everything a background pass does is resumable by construction : the work left is a question the store answers, so stopping between two batches loses nothing. Reporting a budgeted run as a failure, which is what a cancelled task did on every single one of them, tells the scheduler the opposite and teaches it to grant time less often, which is the one thing a task whose budget keeps expiring least needs. The deadline is threaded into the fetching itself instead, so a pass ends between two feeds with a partial summary rather than being cut off mid-write.

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

The network settings of section 8 arrive with the settings screen : Wi-Fi only, the monthly cellular cap, and Low Power Mode as a preference rather than the hard rule it is today. Until then the notifications panel says plainly when Low Power Mode is what has gone quiet, since an application that stays silent about the reason looks broken rather than obedient. The interval correction for sources that publish on business hours, and the quarantine notice offering to fix or delete a feed, are not written yet either.

## Pictures

The pictures articles carry are asked for from the publisher too, and the same politeness applies : the identifying user agent of this page, a body cap, and a disk cache so a picture already seen is never asked for twice. They are fetched when a screen actually shows one, never in advance and never in a batch : a reader who does not scroll to an article costs its publisher nothing.

Nothing is asked for that the feed did not already point at. The rendered article has always loaded its own images, so this adds no new kind of outgoing request, only the same kind on the list.

**A plain `http` address is raised to TLS at the moment it becomes a request.** App Transport Security refuses one outright, so `http` no longer means an address that is fetched insecurely : it means one that is not fetched at all. The raise happens in `HTTPURL.secured`, at the request rather than at the address, so a feed keeps the identity it was subscribed under, `http` and `https` being two different addresses by `docs/technical/feed-identity.md`. A site with no TLS at all fails either way and fails the same way it did before.
