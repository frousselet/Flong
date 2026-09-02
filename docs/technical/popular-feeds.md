# Popular feeds

What the other readers follow, offered as a third way to find a source.

Section 8 of the specification carries the decision. This page carries the design : where the pool lives, what goes into it and what never does, how ten people are counted without a server to count them, and what has to be set up in the CloudKit container before any of it works.

## What it costs the specification, before anything else

Section 1 says *there is no server, no account to create, no hosting*, and section 20 says *no data leaves the device, apart from the private CloudKit database and the requests to the feeds themselves*. A pool of what everybody follows contradicts the second of those sentences, so it amends it in the same commit or the reference stops being one. `docs/technical/collaboration.md` made the same argument for a shared collection, and the shape of the answer is the same.

**What does not change**, and it is most of it. There is still no server, no account of ours and no backend service : the pool is the public database of the container Apple already gives us, the reader's own data still lives in their private database, and none of it reaches us. We still collect nothing, so the nutrition label stays a label that declares no collection *by us*.

**What changes** is one sentence and it is a real change : a reader who says yes publishes the addresses of the sources they follow into a database that every copy of Flong can read.

**What is asked before it does.** Nothing of a reader's is published until they have answered the question, and the question is asked once, on the page itself. Reading the pool never requires contributing to it : conditioning the one on the other would be extorting the consent rather than asking for it, and an extorted consent is not one section 20 could stand behind.

## What travels, and what never does

An address, a name and the site behind it. There is nowhere in the record to put a reader, a date, a count, an article, or a word of anything anybody wrote, which is the same argument `SharedEntry` makes for a collection handed to a named participant, made harder because this goes to everybody rather than to people the reader picked.

**Six reasons to hold a source back**, all of them in `PooledFeed.offered(_:secret:hasCredential:)` rather than scattered over the publisher and the interface. The one that gets forgotten on a path somebody adds later is a reader's private address in a list the whole world reads.

- The reader took this source out of what they offer, source by source, in its own editor.
- Its address is itself the subscription, so the store holds the masked form of section 9 and there is nothing here anybody could follow.
- It has a credential, so it is not a source anybody else can read anyway.
- Its address carries a parameter the reader designated as theirs, or one that only ever said who sent them.
- Its host is not one another reader could reach : a machine on a network, an address literal, a name reserved for not resolving.
- It has never once been fetched successfully, so offering it would be offering a broken address.

**A designated parameter holds the whole source back rather than being stripped off it.** `PublicURL` exists to trim an address that leaves the device, and it is used here as a test rather than as a filter : if trimming would change the address, the source is not offered. What is left of `?token=` is a different address and frequently not a feed at all, and handing somebody a half-address is worse than handing them nothing.

**Nothing that arrives is believed.** A public database takes a record from anybody with an iCloud account. Every address that comes back goes through `FeedURL.canonical(_:)`, which is what refuses a scheme nobody should be asked to open and an address with a password written into it ; every name is stripped of control characters and cut to a title's length ; a list longer than one reader could plausibly follow is cut, which is what stops one contributor from filling everybody else's database.

## The shape of the records

**One record per contributor, never one per source.** The argument of section 7 made a second time : a pool of a thousand readers following three hundred sources apiece is three hundred thousand records in the shape that looks obvious, and a thousand in this one. Each person writes only their own list and reads everybody else's, so two people offering the same source at the same moment cannot collide and there is no conflict to resolve. It is the shape the stream archives and the shared collections already use.

| Record type | Written by | Contents |
| ----------- | ---------- | -------- |
| `PoolList` | every contributor | one chunk of their list of addresses, compressed |
| `PoolRoster` | the author alone | who is believed on their own |

**Named after an identifier of the reader's own making**, kept in their key-value store and therefore the same on their iPad as on their phone. Deliberately not derived from their iCloud identity : a record name in a database the whole world reads should say nothing about who wrote it, and a name nobody can work out in advance is also a name nobody can take first to stop somebody publishing.

**Written only when it changed.** A digest of what was last published is kept locally, so a launch that changed nothing writes nothing. It is the politeness of section 8 pointed at CloudKit rather than at a publisher.

## Counting ten people without a server

CloudKit answers questions about records and has no notion of an aggregate. There is no query that returns *the addresses at least ten people follow*, and there could not be one without something keeping a tally, which is the thing this product does not have. So the counting happens on the device : the lists are pulled as they change, folded into `pool_list` and `pool_entry`, and the question is a `GROUP BY` on a database that already holds a hundred thousand articles and will not notice.

```sql
SELECT e.url, COUNT(DISTINCT l.creator) AS subscribers, MAX(t.creator IS NOT NULL) AS endorsed
FROM pool_entry e JOIN pool_list l ON l.record_name = e.record_name
LEFT JOIN pool_trust t ON t.creator = l.creator
WHERE NOT EXISTS (SELECT 1 FROM feed f WHERE f.url = e.url)
GROUP BY e.url HAVING endorsed = 1 OR subscribers >= 10
```

**A person is counted once.** The count is over `creator`, which is the `creatorUserRecordID` CloudKit stamps on every record : the server sets it and a client cannot, which is the whole reason the count means anything. A contributor able to write somebody else's name into a field of their own would be ten people by dinner time. It also means a reader with a phone and an iPad is one reader, and a list long enough to need three records is one offer.

**Ten is ten Apple accounts**, not ten taps. It is not proof against somebody determined to make accounts, and it does not need to be : what is being decided is whether to show a feed address in a list of suggestions.

**What the reader already follows is taken out in the query** rather than after it. Filtering afterwards would spend the limit on rows nobody sees, and a reader who follows the forty most popular sources would be shown an empty page with forty things behind it.

**A source is called what most of the pool calls it**, which is one line of a second query and is what stops a single bad actor from titling somebody else's feed.

**Resumed from a date rather than from a token.** A public database offers no change token, so what is stored is the modification date of the most recent list already folded in, and the query asks for that date and after it. A record written in the same second as the last one seen is fetched twice rather than missed, and folding a list in twice is the same as folding it in once. A pass is capped and the next one resumes, which is the rule section 15 states for every long task.

**Bounded on the device.** Past two thousand contributors the least recently changed lists are dropped, which is the right ones to drop : a list nobody has touched in a year belongs to somebody who has stopped reading.

## Who is believed on their own

A pool needs an answer for its first day. Ten readers following the same source is a good signal and it does not exist until there are readers, so a new installation would open on an empty page for as long as it took the pool to fill. The roster is the answer : a handful of people whose offers count at once rather than counting for one.

**It is a record, not a constant in the source.** A list compiled into the application could only change by shipping a new one through review, which is weeks to add one person and weeks to remove one who turned out to be a bad idea.

**It is believed from exactly one writer.** Anybody may create a record of that type, as anybody may create anything in a public database, so a roster is worth nothing for existing. What makes one authentic is that CloudKit says the author wrote it : `PoolTrust.root` holds the author's own user record name, every roster in the database is checked against it, and every other one is ignored. That is also what makes squatting the record name pointless, since the roster is found by type and filtered by creator rather than fetched by name.

**`PoolTrust.root` ships empty**, and everything to do with the roster does nothing while it is : nobody is trusted, no roster is believed, and the pool falls back on the count alone. That is a pool that works and starts slowly rather than one that is wrong. Filling it in takes one value, obtained once :

1. Turn the switch on in the reader's panel, on a device signed into the author's iCloud account.
2. The row underneath shows the contributor code, which is that account's user record name in this container. It is opaque, it is not an Apple account identifier, and there is nothing in it to protect.
3. Write it into `PoolTrust.root`, and ship.

From then on the panel shows a roster section on that device and no other, and anybody who wants to be on it hands over their own contributor code, which their own panel shows them for the same reason.

## What the container needs

The public schema is not created by the code and has to be deployed. In the CloudKit console, for the container `iCloud.com.rslt.Flong` :

| Record type | Field | Type | Index |
| ----------- | ----- | ---- | ----- |
| `PoolList` | `feeds` | Bytes | none |
| `PoolList` | `modifiedTimestamp` | system | **queryable, sortable** |
| `PoolRoster` | `trusted` | List of Strings | none |
| `PoolRoster` | `recordName` | system | queryable |

Security roles stay as CloudKit creates them : `_world` may read, `_icloud` may create, `_creator` may write and delete. World read is what lets a reader with no iCloud account see the suggestions ; creator-only write is what stops anybody from touching somebody else's list. Nothing else is granted, and in particular no role may write another's record.

Both record types have to be deployed from development to production before a shipped build can see anything.

## What must not go wrong

**A secret in the pool.** The six reasons above, in one function, tested one by one. The test that matters most is the one asserting that a designated parameter holds the whole source back rather than trimming it.

**A reader who cannot get out.** Turning the switch off deletes the records rather than leaving a list that stops being updated, and deleting everything withdraws the offer before it forgets the identifier the records are named after. That last one is the only part of the erasure of section 20 that reaches outside the reader's own account.

**A list that becomes a fingerprint.** It cannot be avoided and it is stated rather than tidied away : every record carries the opaque identity CloudKit stamps on it, so one reader's addresses are one list, and a list of three hundred addresses is particular to a person even when nothing in it is a name. That is what the footer under the switch says, and it is why the switch is off until somebody says otherwise. A reader who wants a source kept out of it takes that source out, one at a time, in its own editor.

**A pool full of rubbish.** The threshold is the answer for the ordinary case and the majority name is the answer for a title written to be read by somebody else. Neither is proof against a determined nuisance, and the roster is what makes the page useful while the pool is small enough for one to matter.
