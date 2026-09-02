# Popular feeds

What the other readers follow, offered as a third way to find a source.

Section 8 of the specification carries the decision. This page carries the design : where the pool lives, what goes into it and what never does, how ten people are counted without a server to count them, and what has to be set up in the CloudKit container before any of it works.

## What it costs the specification, before anything else

Section 1 says *there is no server, no account to create, no hosting*, and section 20 says *no data leaves the device, apart from the private CloudKit database and the requests to the feeds themselves*. A pool of what everybody follows contradicts the second of those sentences, so it amends it in the same commit or the reference stops being one. `docs/technical/collaboration.md` made the same argument for a shared collection, and the shape of the answer is the same.

**What does not change**, and it is most of it. There is still no server, no account of ours and no backend service : the pool is the public database of the container Apple already gives us, the reader's own data still lives in their private database, and none of it reaches us. We still collect nothing, so the nutrition label stays a label that declares no collection *by us*.

**What changes** is one sentence and it is a real change : a reader who says yes publishes the addresses of the sources they follow into a database that every copy of Flong can read.

**The pool is closed, and reading it is not.** Anybody may see what it holds ; only somebody another member brought in may add to it. That is the answer to the question a public database always raises, which is who is accountable for what appears on the page.

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
| `PoolList` | every member | one chunk of their list of addresses, compressed |
| `PoolVouch` | every member | who they brought into the pool |
| `PoolAuthority` | the author alone | who counts alone, who is cut out, which addresses are withheld |

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

**Only a member counts.** The counting query joins `pool_authorised`, which is the walk written down after every pass, so a list from somebody the graph does not reach contributes nothing even in the case where it was stored before they were cut out.

**A person is counted once.** The count is over `creator`, which is the `creatorUserRecordID` CloudKit stamps on every record : the server sets it and a client cannot, which is the whole reason the count means anything. A contributor able to write somebody else's name into a field of their own would be ten people by dinner time. It also means a reader with a phone and an iPad is one reader, and a list long enough to need three records is one offer.

**Ten is ten Apple accounts**, not ten taps. It is not proof against somebody determined to make accounts, and it does not need to be : what is being decided is whether to show a feed address in a list of suggestions.

**What the reader already follows is taken out in the query** rather than after it. Filtering afterwards would spend the limit on rows nobody sees, and a reader who follows the forty most popular sources would be shown an empty page with forty things behind it.

**A source is called what most of the pool calls it**, which is one line of a second query and is what stops a single bad actor from titling somebody else's feed.

**Resumed from a date rather than from a token.** A public database offers no change token, so what is stored is the modification date of the most recent list already folded in, and the query asks for that date and after it. A record written in the same second as the last one seen is fetched twice rather than missed, and folding a list in twice is the same as folding it in once. A pass is capped and the next one resumes, which is the rule section 15 states for every long task.

**Bounded on the device.** Past two thousand contributors the least recently changed lists are dropped, which is the right ones to drop : a list nobody has touched in a year belongs to somebody who has stopped reading.

## Who may put anything in

**Sponsorship, walked on the device.** The author is in by construction. Everybody in may bring somebody else in. Each member publishes a record naming who they sponsor, CloudKit stamps that record with its writer, and every device walks out from `PoolTrust.root` and keeps whoever it reaches. A sponsorship therefore cannot be claimed on somebody else's behalf : you cannot write a record whose creator is not you.

**Banning takes the branch with it.** A ban that left the banned person's own invitations standing would be no ban at all, since anybody about to be cut out would sponsor ten accounts first. Being reached means being reached through people who are all still in, so cutting one person cuts everybody who came in through them and nobody else. That is what makes a sponsorship an undertaking rather than a favour, and the interface says so under the field before anybody uses it.

**Twenty each.** One member may bring in twenty people. It bounds how fast the pool can grow, keeps a sponsorship a personal act rather than a broadcast, and keeps a single careless member from opening the pool to a crowd. The cap is applied against a sorted list when a record is read, so every device agrees on which twenty.

**Nothing here stops a write.** A public database takes a record from any iCloud account, and no CloudKit role can be denied to one person, so what the author holds is not the power to silence a device but the power to make what it says count for nothing, everywhere, from the next pass. Two things follow. The application declines to publish at all until it has seen itself reached, so an unsponsored reader writes nothing in the ordinary case. And a list whose writer is not reached is never stored, so a client written to misbehave costs every other reader's device nothing.

**If it ever got bad enough**, the escape hatch is a console action and not a new build : move the create permission on `PoolList` from `_icloud` to a custom role. Nothing in the application changes, and the pool stops accepting writes from anybody not in that role.

## Who is believed on their own

A closed pool starts with one member, so nothing would ever reach ten. The author's own list, and a handful of members they name, count at once rather than counting for one. It is the same record as the ban list and the withheld addresses, because they are one decision made in one place : see below.

## What the author decides, in one record

`PoolAuthority` carries three lists and is believed only from `PoolTrust.root`. A device that read two of the three would be acting on half an instruction, so it is one record and one fetch.

| Field | What it holds | What it does |
| ----- | ------------- | ------------ |
| `trusted` | contributor codes | their offers count at once rather than counting for one |
| `banned` | contributor codes | cut out, along with everybody they brought in |
| `blocked` | digests | addresses never suggested, whoever follows them |

**A withheld address travels as a digest and never in the plain.** One reason to withhold an address is that it should never have been public in the first place, and a list of forbidden addresses published in the open would broadcast exactly the thing it exists to hold back. Half a SHA-256 tells addresses apart and says nothing about any of them. The consequence is that only the device that made the decision can show its reader what it withheld : the plain address is written to `pool_block` there and nowhere else, and every other device shows a digest and says so.

**Aiming a ban needs a name.** A bad suggestion is visible on the page ; the accounts behind it are not. The author's own device, and no other, can open a suggestion on the list of contributor codes that offered it, and cut one of them out from there. Without that the only available repair would be withholding addresses one at a time for ever.

## The anchor, and why it is written in the open

`PoolTrust.root` is set. It is the author's own contributor code : that account's user record name in this container, which is what CloudKit stamps on anything they write. It was obtained once, the way anybody obtains theirs : turn the switch on in the reader's panel on a device signed into that account, and read the row underneath.

**It ships in the binary and that is not a leak.** It is compiled into every copy of the application, so it is on every device that installs one and can be read out of the binary by anybody who cares to. An anchor that were secret would be no anchor : every device has to know where the walk starts, or the walk cannot happen on the device, which is the whole shape of this.

**Nothing authorises anybody for presenting it.** Every trust decision here reads `CKRecord.creatorUserRecordID`, which the server stamps and no client can write : `PoolAuthority.read` refuses a record whose creator is not the root, and `PoolVouch` takes the sponsor from the creator and never from a field. So knowing the string lets nobody sponsor, ban, block or vouch for anything, and a record claiming to be the author's is worth nothing for saying so. It is also not an Apple account identifier : it is opaque, it is scoped to this container alone, and it carries no name, no address and nothing about the same account anywhere else.

**What it does cost** is that it is fixed for every copy already shipped. Moving the anchor is a new version, and the copies out there keep walking from the old one, which for a closed pool means their page empties rather than fills with the wrong thing. That is the safe way round, and it is the reason to set it once and leave it.

**`nil` is still what safety looks like.** In a closed pool it means nobody is in at all, so a build with no anchor shows nothing rather than showing what nobody vouched for.

From here on the author's device shows the sections nobody else's does, and anybody who wants in hands their own code to a member.

## What the container needs

The public schema is not created by the code and has to be deployed. In the CloudKit console, for the container `iCloud.com.rslt.Flong` :

| Record type | Field | Type | Index |
| ----------- | ----- | ---- | ----- |
| `PoolList` | `feeds` | Bytes | none |
| `PoolList` | `modifiedTimestamp` | system | **queryable, sortable** |
| `PoolVouch` | `sponsored` | List of Strings | none |
| `PoolVouch` | `recordName` | system | queryable |
| `PoolAuthority` | `trusted`, `banned`, `blocked` | List of Strings | none |
| `PoolAuthority` | `recordName` | system | queryable |

Security roles stay as CloudKit creates them : `_world` may read, `_icloud` may create, `_creator` may write and delete. World read is what lets a reader with no iCloud account see the suggestions ; creator-only write is what stops anybody from touching somebody else's list. Nothing else is granted, and in particular no role may write another's record.

All three record types have to be deployed from development to production before a shipped build can see anything.

## What must not go wrong

**A secret in the pool.** The six reasons above, in one function, tested one by one. The test that matters most is the one asserting that a designated parameter holds the whole source back rather than trimming it.

**A reader who cannot get out.** Turning the switch off deletes the records rather than leaving a list that stops being updated, and deleting everything withdraws the offer before it forgets the identifier the records are named after. That last one is the only part of the erasure of section 20 that reaches outside the reader's own account.

**A list that becomes a fingerprint.** It cannot be avoided and it is stated rather than tidied away : every record carries the opaque identity CloudKit stamps on it, so one reader's addresses are one list, and a list of three hundred addresses is particular to a person even when nothing in it is a name. That is what the footer under the switch says, and it is why the switch is off until somebody says otherwise. A reader who wants a source kept out of it takes that source out, one at a time, in its own editor.

**A pool full of rubbish.** Four answers, in the order they apply. Nobody writes who was not brought in by somebody. Ten members still have to agree, and the majority name answers a title written to be read by somebody else. A member who abuses it is cut out along with everybody they brought in. And an address that should never be suggested is withheld whoever follows it. None of it is proof against somebody determined, and none of it needs to be : what is being decided is whether an address appears in a list of suggestions.

**A sponsorship chain nobody is watching.** The cap of twenty and the branch-cutting ban bound the damage, but they do not remove the fact that a member three hops from the author can bring in somebody nobody else has heard of. That is the price of not having a server to hold a queue of approvals, and it is a deliberate trade : the pool grows without the author being a bottleneck, and the repair when it goes wrong is one ban rather than a purge.
