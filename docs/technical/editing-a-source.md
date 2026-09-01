# Editing a source

What a reader may change about a source they follow, and what the address drags along when it is the thing that changes.

## Why it is a subject of its own

Three of the four fields are ordinary. A name, a site and an interval are columns of `feed`, written in one statement, and nothing else in the store has an opinion about them.

The address is not a field. **A feed is identified by its URL** (`docs/technical/feed-identity.md`), and every record the reader's iCloud holds about a source is named after that URL : the subscription itself, each article they marked under it, and every block of its stream this device wrote. Change the address and none of those names is right any more, on any device.

It is worth the trouble because the alternative is worse. Until this existed, a publisher who moved their feed cost the reader everything under it : the only repair was to unsubscribe and subscribe again, which is `docs/technical/removing-a-source.md`, which takes the articles, the stars, the notes and the filings, and carries that removal to every device the reader owns. A feed that moves is an ordinary event and it should cost nothing.

## Where it lives

In the sources panel, in the menu a source's own row opens, between the favourite and the removal. It opens the editor, and the editor holds everything there is to say about one source : its name, its address and whether that address is a secret, the parameters on its addresses, the site it belongs to, how often it is asked, whether it is one of the reader's favourites, and its health.

Every field is written on every save, so what the editor sends is the whole of what the reader was looking at. `SourceEdit` is that state and nothing else : text for what is typed, since text is what a reader types, and the canonicalization happens once, in the store, under the rules identity already follows.

The parameters of its addresses are in it too, as toggles against what the feed's address and its recent articles actually carry. They were a screen of their own behind a second line of the same menu, which is one place too many for something that is plainly a property of this source. `docs/technical/credentials.md` covers what a designation means and where it is applied.

The health of the source is shown and cannot be edited : when it last answered, the share of answers that were `304`, and how many failures stand in a row. Section 8 asks for the 304 rate to be surfaced in the feed settings, and this is where the feed settings are.

## What a change of address does here

One transaction, because a source half moved is a row pointing at an address nothing else in the store agrees with.

| Where | What happens | Why |
| ----- | ------------ | --- |
| `feed.url` | Set to the canonical form of what was typed | Everything that identifies a source is this column |
| `feed.previous_url` | Set to the address it left | It is what lets the move travel : see below |
| `feed.etag`, `feed.last_modified` | Cleared | They were issued by the server it left. Replayed at another they ask about somebody else's file, and a `304` would keep the new address empty for as long as the reader waited |
| `feed.fetch_count`, `not_modified_count` | Reset | A 304 rate mixing two servers' answers measures neither |
| `feed.failure_count`, `last_failure_reason`, `quarantined_at` | Cleared | A reader editing an address is usually repairing a source that had stopped answering, and the quarantine is exactly what they are undoing |
| `feed.last_fetch_at`, `last_success_at` | Cleared | Which makes it due at once, and it is fetched before the sheet is closed |
| `pending_mark` | Re-keyed onto the new address | A mark waiting for an article is keyed by the address it arrived under, which is all it has to find its article by. Left behind it would wait for ever on an address nothing is going to ask for again |
| `source_name` | The name over the old publisher goes, when the move was the last source leaving it | A group is worked out from the addresses of its feeds and never survives them |

The entries are not touched at all, which is the whole point : they are keyed by `feed_id`, and the source has not gone anywhere.

**The read states need nothing.** A fingerprint is a digest of the feed address and the article's identity together, so every one of them for this source is wrong the moment it moves. Nothing is rewritten : `ReadStateStore.compact` builds the blocks from the feeds as they now stand and merges, so the next compaction adds the right fingerprints, and merging is a union so the old ones stay. They are a few bytes each, they match nothing, and no device is ever told that an article it had read is unread.

## What goes outside the store

**iCloud, twice over.** The old names are deleted, through the same path a removal uses : the subscription, one record per article the reader had marked under it, and every block of that feed's stream, found in `sync_record` by the prefix the old address hashes to. The new names are then queued : the subscription again and the marks again, under the digest of the address the source now has.

**Spotlight.** The name of a publisher is on every article of theirs the index holds, and a favourite source is what put those articles in it at all, so the index and the store are asked to agree again.

**The keychain**, when the address that changed is itself a secret. It goes to the keychain first, and the row is moved after : should the second half fail, a feed fetched with the secret it was given goes on working under an identity one move behind, where the other order would leave a source at an address whose secret nothing knows.

## Secret, or not

Whether an address is a secret is a fact about the address rather than a setting beside it, so it is a switch in the address section, and moving it moves the source through the same path as any other change of address.

- **Making one secret** masks the row, writes the real address to the keychain, and deletes the records the plain address was in : it is the only way a reader who pasted a per-subscriber address without saying so can get it out of their own iCloud. The whole of what was under it stays.
- **Making one open** writes the address back into the database and into iCloud, in the open, which the screen says before it is asked for. Flong uses the address the keychain holds unless the reader types another ; with neither, it is refused rather than leaving a source at an address nothing knows.
- The keychain is written before the row and cleared after it. A secret stored for a source that did not move is a secret nothing will use ; a secret cleared from one that did is a source that is simply broken.
- The address is shown as dots and read out on a deliberate tap, in this editor and nowhere else. It is masked, which is what section 9 asks for, and it is reachable, which a digest is not : a reader whose platform reissues their token has to be able to see what they are editing.
- The parameters below it are read against that same real address. The masked form carries none, so a screen that would not look at the keychain reported that a feed with a token in its query string had no parameters at all.

## Carrying the move to the other devices

The obvious implementation is a save under the new name and a deletion under the old one. On another device that pair reads as one subscription removed and another one added, and the removal takes the articles of a source that has not gone anywhere.

So the record says where the source came from. `previousURL` travels on the `Feed` record, and a device applying it moves the row it already holds to meet the record before the ordinary upsert runs. The deletion that follows finds no feed at the old address and takes nothing. Modifications are applied before deletions within a batch, which is what makes the usual case the safe one.

The move is idempotent by construction. A device with nothing at the old address does nothing ; a device that already has something at the new one does nothing ; a record replayed a second time does nothing. There is no state anywhere saying whether a device has followed a move, and none is needed.

`previous_url` is never cleared, because the device that needs it is the one that has been switched off for a year.

**What it does not cover**, and this is the honest bound : a device that misses an intermediate address change falls back to the old behaviour. A source moved from A to B and then from C, while a device sat offline, leaves that device with a record naming a previous address it has never held, and the deletion of A that it also receives removes the row and its articles. The marks are re-queued under the current names and are reapplied as the articles come back, so what is lost is the articles that had already fallen out of the feed's own window. Two moves of one source while a device is off is rare enough to be worth this, and cheap enough to be worth saying.

## What a reader's own decisions do now

The upsert has always completed a feed and never overwritten it : a title they changed, a site they corrected and a source they made a favourite outrank whatever a re-import carries. That is right for an import and was wrong for what arrives from iCloud, where the later word is the one the reader meant. `SubscriptionStore.adopt` is what says so, applied over the upsert rather than through it, and it is what carries a name written on an iPad to the phone in the reader's pocket. A field the record does not state is not a decision to unset it : an older record carries no favourite, and nothing said is not the same as `no`.

## What is tested

That the address behind a masked one is read back for the field that edits it and for the parameters below it ; that a source made secret is masked with its address in the keychain and its articles untouched ; that one made open again is written back in the open with the keychain emptied ; that one made open with no address anywhere is refused rather than broken ; that a new secret address replaces the one held and moves the source ; that changing anything else on a secret source leaves the secret alone ; that the parameters offered are the ones the feed and its articles carry, that a masked address is not among them and its articles' still are, and that a designation is folded. And, at the store : that a rename leaves the source where it is ; that an empty name falls back to the host it now has ; that a move keeps the articles and reports the address it came from and the articles the reader had marked ; that a move onto an address already followed is refused and changes nothing ; that an address Flong cannot follow is refused ; that a move forgets the conditional state, the health record and the quarantine ; that the waiting marks follow and another source's stay ; that the name over an emptied publisher goes and the name over a publisher still served stays ; that the site is what a source is grouped under ; that a manual interval is held inside the bounds of section 8 ; that a move arriving from another device moves the row rather than adding one, twice over and onto a taken address ; and that what another device decided about a name, a site or a favourite is adopted, while a record that says nothing about one takes nothing back.
