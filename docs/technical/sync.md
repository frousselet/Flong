# Synchronization

The reader's own private CloudKit database, and nothing else. No server, no account to create, no third party. A device without iCloud is not a broken device : section 3 says Flong is fully usable on one, and the sidebar stays quiet rather than complaining.

`CKSyncEngine` owns everything that is hard about synchronization : the scheduling, the batching, the subscriptions, the retries and the backoff. Flong answers the two questions it cannot, which is all `SyncPayload` does : what this device has to say, and what to do with what it hears.

## The budget is the design

CloudKit degrades on record count and change throughput, not on bytes. Around three thousand records over three years is the target, and everything below follows from it.

| What | How many | Why that many |
| ---- | -------- | ------------- |
| feeds | a few hundred | one per subscription |
| library items | one to two thousand | one per kept article, content and all |
| read-state blocks | a few dozen | **one per month**, over every feed |
| catch-up headers | a few hundred, sliding | one per feed and per day, over thirty days |

One record per article would be more than a hundred thousand over the same period, which CloudKit rate limits into uselessness.

## Names are derived, never local

Every record is named after **what it is about** : a digest of the feed address, or of the feed address and the article's identity. Two devices that star the same article compute the same name and write the same record, so CloudKit sees one row and not two. A name derived from a local identifier would give every device its own copy of everything.

## Read states

The whole budget rests on this. Read states travel as one record per month, holding the fingerprints of everything read in it.

- **A fingerprint** is eight bytes of a digest of the feed address and the article's identity. Two devices work it out alike without having spoken. Over the target corpus, two colliding is about one chance in five thousand million, against a cost of one article marked read that was not.
- **The period is the month the article was published in**, never the month it was read or received : those differ from one device to the next, and a block whose name depended on them is a block no two devices could agree on.
- **Merging is a union**, so it is commutative and idempotent and there is no conflict to resolve. Two devices that read different articles in August both end up with both.
- **Reading is therefore one way.** Marking an article unread is a local decision and does not travel : a set that only grows has nothing to say about what left it. That is the price of having no conflict resolution at all, and it is the right price.
- **A block that arrives is kept, not merely applied.** An article read elsewhere may not have been fetched here yet, and when it arrives it has to arrive read.

Starred articles are deliberately **not** in these blocks. Starring is what puts an article in the library, and a library item is a record with a real deletion, so it travels as itself and unstarring travels with it.

## What never travels

The articles of the stream, the indexes, and the health of a feed. The stream is a cache each device fills for itself, and a copy of it would be both enormous and worthless. A feed's `ETag`, its counters, its observed interval and its quarantine are what *this* device knows about its own fetching ; telling another device would be telling it something untrue.

Secrets never travel either, and nothing in this direction ever will : section 9 keeps them in the keychain, which has its own synchronization.

## Catching up

A feed holds twenty articles ; a device left off for a week comes back to find half of what its other devices saw has scrolled out of it for good. One record per feed and per day carries identifiers, titles, links and dates, over a sliding window of thirty days, and records that fall out of the window are deleted. The bodies are not sent : a caught up article arrives as a title and a link, which is enough to decide whether to go and read it, and the next refresh fills in the rest when the article is still there.

## When CloudKit says no

| Answer | What it means | What Flong does |
| ------ | ------------- | --------------- |
| `quotaExceeded` | the reader's iCloud is full | says so, and offers to purge the stream |
| `requestRateLimited` | slow down | waits until `CKErrorRetryAfterKey` |
| `serviceUnavailable`, code 6 | **also** slow down | the same, since this is the frequent one in practice |
| `serverRecordChanged` | two devices wrote at once | merges, which for a read-state block is a union |
| `zoneNotFound` | the zone was deleted | recreates it and queues everything again |
| `notAuthenticated` | no account | stays quiet : this is not an error |

Treating only the documented name for rate limiting is how a client ends up hammering a service that already told it to stop.

## What is tested, and what cannot be

`CloudSync` is the one file of the project that cannot be tested from the outside : it needs an account, a container and a network, none of which a test may assume. Everything on either side of it is tested instead, with records carried between two stores by hand : setting up a second device from records alone, read states meeting in the middle, deletions travelling, the same records applied twice changing nothing, two devices keeping one article, and a device catching up on what it missed.

The container is `iCloud.com.rslt.Flong`, and the entitlement is in `Config/Flong.entitlements`.
