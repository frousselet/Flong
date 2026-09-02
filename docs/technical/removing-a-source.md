# Removing a source

What goes when a reader stops following a feed, what goes with a whole publisher, and the three things that stay.

## Why it is a subject of its own

Unsubscribing looks like deleting a row and is not. A feed is the only thing in the store that other things exist *because of* : its articles, their bodies, their rows of the index, their place in a story, the collections they were filed into, the secret it is fetched with, what Spotlight was handed, and the records the reader's iCloud holds for all of it. Most of that leaves on the foreign keys. The rest leaves because this path takes it, and anything it forgot would be a row pointing at something that no longer exists, on a device nobody is going to inspect.

It is also the second command in Flong that cannot be undone. `docs/technical/erasure.md` covers the first, which takes everything ; this one takes one publisher's worth and spares the rest, and both say what will go before they do it.

## Where it lives

In the sources panel, in three places that are one action : a swipe on the trailing edge of a source, a long press on it, and the menu the heading of a publisher opens. The trailing edge is where the system puts a deletion and where a reader reaches for one ; the heading is already the only place a group is acted on, and removing the publisher is the second thing it does after naming it.

None of the three acts. Each one asks, in an alert that names what is being removed and says that the articles going with it include the ones the reader starred, wrote on or filed. A swipe that went further than intended costs a tap, not a publisher.

**A group is not a row.** Removing a publisher is removing its sources, in one transaction : there is nothing else of it to delete, and the heading goes because the last thing under it did.

## What the store takes away

| Where | What goes | How |
| ----- | --------- | --- |
| `entry` | Every article of the feed | `ON DELETE CASCADE` on `entry.feed_id` |
| `entry_body` | Their text, both versions | Cascade on `entry_body.entry_id` |
| `entry_fts` | Their rows of the full-text index | The delete trigger of the schema |
| `story_member` | Their place in a story | Cascade on `story_member.entry_id` |
| `story`, `story_topic` | Any story the removal left with fewer than two articles | `StoryBuilder.removeEmptyStories(in:)`, cascade for the subjects |
| `tag_binding` | Their filings into made collections | By hand : a binding names its target by kind and carries no key |
| `pending_mark` | Marks waiting for articles that will never arrive now | By hand : keyed by the address of the feed, not by a row of it |
| `source_name` | The name written over the publisher, when this was its last source | By hand, and only then |
| `entry.duplicate_of` | Elsewhere : a second copy of one of its articles stops being a duplicate and becomes the article | `ON DELETE SET NULL` |

Four of those are done by hand because no key reaches them, and each is a leak of a different shape. A filing left behind is a collection counting an article that has gone. A waiting mark is a row for an article no feed will ever serve again. A story of one article is a headline over nothing on the front page. And a name left over a publisher nobody follows is a row no screen shows, no screen edits, and that would silently reappear over the group if the reader ever subscribed to that publisher again.

It is one transaction. A source half removed would be worse than one not removed at all, since nothing would ever try again.

## What goes outside the store

**The keychain.** The credential is keyed by the row that has just gone, so a moment later nothing in the application could name it : it would sit there, unreachable, until the reader deleted everything. Section 20 of the specification is careful about exactly this, so the secret goes first. The site sessions do not : see below.

**Spotlight.** The marks are taken back by identifier, since that is what they are known by. What a favourite source or a favourite writer had chosen is not : it was never a mark, and it leaves with the rows rather than through a decision anybody made. So the removal ends by asking whether the index and the store still agree, which they no longer do, and the index is written again. Taking them out now is what keeps a system search from opening an article that is not there.

**iCloud.** Four kinds of record, queued for deletion through the engine :

- the subscription, which is what carries the removal to the reader's other devices ;
- one record per article they had marked under it, since a mark is the one thing here that is theirs rather than the publisher's ;
- every block of that feed's stream this device wrote, which is the bulk of them ;
- the name they had written over the publisher, when the source that went was its last.

The blocks are found by name rather than worked out. A record name is a digest and cannot be read backwards, the days are gone with the articles, and the number of chunks a busy day was cut into was never known anywhere but in the names themselves. `sync_record` is the ledger of what this device actually saved, so what it holds under `catchup-<digest of the feed>-` is exactly the set to delete. The tags of the deleted records are forgotten by the ordinary deletion path, which is where every deletion already forgets them.

## A removal that arrives from another device

`SyncPayload` applies it through the same store removal rather than deleting the row. A source that goes because another device said so has to go exactly as one removed here does, or every device except the one that was asked keeps the filings, the waiting marks, the emptied stories and the orphaned name, for ever and invisibly.

Nothing is queued back : the device that removed it has already deleted every record, and this end has only to catch up.

## A removal that never arrived

The deletion of the subscription record is what carries the removal, and for a long time it was the one change in the application that could be lost without trace. The intention lived nowhere but in the sync engine's pending changes : no engine at the moment of the removal, a reset, or one refusal from the server, and the source stayed on the reader's other device for good, with nothing anywhere that would ever try again. It is written down before it is queued now, and `docs/technical/sync.md` sets out the four ways it used to go missing.

That fixes the next removal and not the last one, because a deletion that was lost is not a change the server will ever mention again. `Tidy the sources`, in the reader's own panel, is the repair for a device already wrong : it reads the zone as it stands and offers to remove every source here whose record is not in it. It removes nothing on its own, since a source going takes the whole of the table above with it, and the removal it then performs is this one.

## What is not touched

**The session on the site.** A session is keyed by the site the cookies claim, which is usually broader than the group a source falls under : one sign-in covers every feed and every article of `lemonde.fr`, including sources under `abonnes.lemonde.fr`. It is also the reader's own relationship with a publisher rather than a property of a subscription, and it is listed in their panel with a way to sign out. Taking it away with a feed would sign them out of a site they may still be reading, in a place they were not looking, so it stays and stays visible.

**The read states.** They are compacted into one block per month over every feed, and merging is a union : reading is one way, so that two devices that read different things in August both end up with both. Removing fingerprints would be the one operation the shape does not support, and another device that still had the feed would put them back at the next exchange. A reader who subscribes again finds what they had already read still read, which is true.

**The archive in iCloud Drive.** It is append-only, one file per device and per day, and no file is one feed's. Nothing brings the articles back, though : `StreamBlock.apply` writes only for feeds this device follows, so a block naming a source nobody follows is read and dropped. The archive shrinks on its own as the days roll past.

## What is tested

That the articles go, that the filings go and the ones of another source stay, that the waiting marks go and the ones of another source stay, that a story left with one article goes, that the name over a publisher goes with the last of its sources and not before, and that removing a publisher removes every source under it and nothing else. At the window : that the removal empties the list and puts the reader back on the whole stream rather than on a heading with nothing under it, and that the secret leaves the keychain.

The iCloud half is the part that cannot be tested from the outside, which is true of everything in `CloudSync` and is recorded in `docs/technical/sync.md`. What is testable of it is tested there : that an intention to delete outlives the moment it was decided, and that the tidying calls a source gone only when the server had confirmed the record it no longer holds.
