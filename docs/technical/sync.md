# Synchronization

The reader's own private CloudKit database, and nothing else. No server, no account to create, no third party. A device without iCloud is not a broken device : section 3 says Flong is fully usable on one, and the sidebar stays quiet rather than complaining.

`CKSyncEngine` owns everything that is hard about synchronization : the scheduling, the batching, the subscriptions, the retries and the backoff. Flong answers the two questions it cannot, which is all `SyncPayload` does : what this device has to say, and what to do with what it hears.

## The budget is the design

CloudKit degrades on record count and change throughput, not on bytes. Around three thousand records over three years is the target, and everything below follows from it.

| What | How many | Why that many |
| ---- | -------- | ------------- |
| feeds | a few hundred | one per subscription |
| marks | one to two thousand | one per marked article : starred, annotation, collections, vector |
| read-state blocks | a few dozen | **one per month**, over every feed |
| catch-up headers | a few hundred, sliding | one per feed and per day, over thirty days |

One record per article would be more than a hundred thousand over the same period, which CloudKit rate limits into uselessness.

## Names are derived, never local

Every record is named after **what it is about** : a digest of the feed address, or of the feed address and the article's identity. Two devices that star the same article compute the same name and write the same record, so CloudKit sees one row and not two. A name derived from a local identifier would give every device its own copy of everything.

## A list that may be empty is written as data

CloudKit works the type of a field out from the first record that carries it, and an empty list says nothing about what it would hold. The server refuses it outright, `cannot use an empty list to initialize a new field`, and refuses the whole batch with it, not just that record.

An empty list is the ordinary case here : starring an article files it in nothing, so the first mark a reader ever makes is the one that fails.

Leaving the field out instead is worse. A field absent from a save keeps whatever the server already holds, so unfiling the last collection off an article would never travel and the other device would go on showing a filing the reader removed.

So a list of names travels as JSON data : `[]` is two bytes, the type is the same whatever it holds, and emptying it is a change like any other. The fields are `Mark.filedIn` and `Collections.made` ; a record written before this change carries the older `collections` and `names` lists, which are still read, and move over on the next write of that record.

## Read states

The whole budget rests on this. Read states travel as one record per month, holding the fingerprints of everything read in it.

- **A fingerprint** is eight bytes of a digest of the feed address and the article's identity. Two devices work it out alike without having spoken. Over the target corpus, two colliding is about one chance in five thousand million, against a cost of one article marked read that was not.
- **The period is the month the article was published in**, never the month it was read or received : those differ from one device to the next, and a block whose name depended on them is a block no two devices could agree on.
- **Merging is a union**, so it is commutative and idempotent and there is no conflict to resolve. Two devices that read different articles in August both end up with both.
- **Reading is therefore one way.** Marking an article unread is a local decision and does not travel : a set that only grows has nothing to say about what left it. That is the price of having no conflict resolution at all, and it is the right price.
- **A block that arrives is kept, not merely applied.** An article read elsewhere may not have been fetched here yet, and when it arrives it has to arrive read.

Starred articles are deliberately **not** in these blocks. A star travels as a mark of its own, which is a record with a real deletion, so unstarring travels with it.

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

## What the server said about each record

CloudKit refuses a record carrying no change tag when it already holds one under that name : `Server Record Changed (14/2004)`, `record to insert already exists`. A record built from the local store alone carries no tag, so **every save after the first was refused, for ever**, and the read-state blocks of the current month failed on every exchange.

The tag travels inside the system fields of the record the server hands back. Those are kept in `sync_record`, written whenever the server says anything about a record : when it hands one over, when it confirms one saved, and when it refuses one and hands back its own copy. A save starts from them and copies the values over.

It is a cache, not a source of truth. Losing it costs one refused save per record, after which the server hands the record back and the tag is learned again. A zone that has gone takes every tag with it.

## Being told rather than asking

`CKSyncEngine` learns of another device's changes through a silent push, not by polling, which is what keeps a second device up to date without draining anything. Two things have to be true for that push to arrive.

**The background mode.** `remote-notification` in `UIBackgroundModes`, beside `fetch` and `processing`. Without it CloudKit refuses to set the subscription up at all and says so : `BUG IN CLIENT OF CLOUDKIT: CloudKit push notifications require the 'remote-notification' background mode in your info plist`. It costs nothing and is declared in `Config/Info.plist`.

**The Push Notifications capability**, which is an `aps-environment` entitlement and, behind it, a capability on the App ID. It is there now, in both spellings the two platforms want : `aps-environment` for iOS and `com.apple.developer.aps-environment` for the Mac.

It is worth writing down how it got there, since the order matters and the wrong order looks like a broken project. Adding the entitlement to the file first fails to sign, with a provisioning error that names the profile rather than the cause : an App ID that does not carry the capability cannot be granted it by a file asking nicely. Enabling it under Signing and Capabilities in Xcode does both halves at once, the App ID on the account and the entitlement in the file, which is why that is the way in.

The same is true of iCloud. The target carries `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.ubiquity-container-identifiers` and `com.apple.developer.ubiquity-kvstore-identifier`, with `CloudKit` and `CloudDocuments` among the services : records for what must merge, documents for the stream archives, and the key-value store for what the reader has chosen. All against one container.

A build for a real device is what proves any of this. The simulator does not check the App ID, so a missing capability signs happily there and fails the moment it meets hardware : `xcodebuild build -destination 'generic/platform=iOS'` is the check worth running.

Without the push the application still synchronizes : the engine sends what is pending and fetches what is waiting whenever it runs, which is at every launch, on returning to the foreground, and on a pull. What is lost is promptness, not correctness.

## The schema, and the day it stops being automatic

The development environment invents the schema as it goes : the first save of a record type creates it, and the first save carrying a new field adds it. Nothing has to be declared, which is why none of this has needed a thought so far.

Production does not. It takes the schema it was given, and a save carrying a field it has never heard of is refused. **TestFlight and the App Store use production**, so the schema has to be deployed from the CloudKit console before the first build that leaves this machine, not after.

The part that catches people is the second time. Adding a field later is invisible in development and fatal in production until it is deployed again : the console's *Deploy Schema Changes* is not a one-off. Anything that changes what `SyncRecords` writes, or adds a record type, is a change to redeploy. The `Mark` record type is the most recent of those, and the `LibraryItem` type it replaces is dead : a production schema is additive only, so it can never be removed, only left unused.

`SyncRecords` is the only description of the schema there is. There is no separate declaration to keep in step, deliberately, since two descriptions of one thing are one description and one lie.
