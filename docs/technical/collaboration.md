# Collaboration

Sharing a collection with somebody who is not the reader.

This is a design note written before any of it exists. It says what Apple gives, what the shape of Flong makes easy and what it makes hard, what must not go wrong, and what I would build in what order. Nothing here is decided.

## The rule that decides everything else

**Only the excerpt the feed published, never the article.**

Three reasons, and each is enough on its own. The article is not ours to hand anybody : the reader did not write it and neither did we. A credential never leaves, in any of the forms it takes, so a cookie is not sent and a secret in an address is truncated out of it. And what a publisher puts in a feed for syndication is the part they chose to make public, so it is the part that can travel.

This was written the other way round first, with bodies travelling compressed. Every hard problem in the rest of this note is smaller because it is not, and two of them disappear outright. It is worth seeing how much of the difficulty was self-inflicted.

## What it costs the specification, before anything else

Section 2 lists among the non-goals : *server, account, multi-user, social sharing*, and separately *collaborative annotation*. This feature is the third of those and stands next to the fourth. That is not a detail to work around quietly : the specification is the reference, and a feature that contradicts a written non-goal amends it in the same commit or the reference stops being one.

**What does not change**, and it is most of it : there is still no server, no account of ours and no backend service. The data moves through the reader's iCloud, between iCloud accounts, and none of it reaches us. The privacy policy and the nutrition label of section 20 stay true, since we still collect nothing.

**What changes** is one sentence, and it is a real change : the reader's data may now reach another person, on purpose, by name, and that person's data may reach them.

## What Apple gives, in three layers

They are usually spoken of as one thing. They are three, they are adopted separately, and only the first is unavoidable.

**CloudKit sharing, which is the data.** A [`CKShare`](https://developer.apple.com/documentation/cloudkit/ckshare) is a record that grants named iCloud users access to data that stays in the owner's private database. Participants reach it through their own **shared database**, `CKContainer.sharedCloudDatabase`. Two shapes : a share rooted on a record and its parent-child hierarchy, or a **zone-wide share**, `CKShare(recordZoneID:)`, which shares a whole custom zone and needs no hierarchy at all. Per participant, a permission of read-only or read-write, and an access of private, meaning invited only, or public, meaning anyone holding the link.

**The share sheet, which is the invitation.** [`CKShareTransferRepresentation`](https://developer.apple.com/documentation/cloudkit/cksharetransferrepresentation) makes a `Transferable` the system understands as a collaboration rather than as a file, so SwiftUI's `ShareLink` puts the collaboration pill in Messages and the system manages the participant list. Its `prepareShare` form creates and saves the share only once a recipient has actually been picked, which is what stops a zone being created for a share nobody sent. `SWCollaborationView`, from `SharedWithYou`, is the button that shows the participants and opens the system's manage-share popover.

**Shared with You, which is the surfacing.** `SWHighlightCenter` puts what was shared with the reader in Messages inside the application. This one is independent of everything else here and is worth a thought of its own : an article link a friend sends in Messages appearing in the reader is a feature that needs no share, no zone and no participant.

**Accepting** is the part with an awkward edge. The share link opens the application and hands it a `CKShare.Metadata` through `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` on iOS and `NSApplicationDelegate.application(_:userDidAcceptCloudKitShareWith:)` on macOS, and the application answers with `container.accept(metadata)`. `FlongApp` is pure SwiftUI today with no delegate of any kind ; one has to be added on both platforms, through the adaptor property wrappers, for this and only this.

**`CKSyncEngine` covers the shared database.** Its own documentation says so : *you can have multiple instances of `CKSyncEngine` in a single process, each targeting a different database. For example, you may have one syncing a person's private database and another syncing their shared database.* So section 7 does not have to be abandoned to do this. It does have to be enlarged, which is the subject of a later part of this note.

## Why a collection cannot simply be shared

Nothing above is difficult. What is difficult is that **Flong's collections have nothing in them**.

A made collection is a tag `collection/<name>` and a set of bindings, and what travels between the reader's own devices is the *pair* : this article, in that collection, as a field on the article's own mark record. That is the whole of the design and it is why a collection costs no records of its own. It works because both ends already hold the article : it arrived because the reader subscribed to the feed, and it crossed between their devices as a stream block or as an archive file.

**A participant has none of that.** They have not subscribed to my feeds, my stream blocks are in my private database and my ubiquity container where they cannot see them, and they have no article for a membership to be about. Send them the pairs and they receive a list of identifiers for articles they do not have.

So something has to travel that is about the article rather than about its filing. That something is the excerpt, and the whole design is what follows from its being small.

## Which of the three natures can be shared, and what each one would mean

Section 13 says the three natures are told apart by what travels. Sharing asks the same question of each and gets three different answers.

| Nature | What sharing it would mean | Verdict |
| ------ | -------------------------- | ------- |
| **Made** | The excerpts of the articles filed in it, and who filed each one | This is the feature |
| **Dynamic** | The description, one small record, and nothing else | Cheap, and it means something else entirely : see below |
| **Built-in** | Starred is an unbounded and growing stream ; notes are the reader's own words about their own reading | Out. Neither is a thing to hand somebody |

**A shared dynamic collection is a lens, not a collection**, and that has to be said in the interface or it is a lie. The description travels and the articles never do, so it answers against the *recipient's* articles : two people opening the same shared dynamic collection see different things, and a recipient following none of the sources the query is about sees nothing at all. Presented as *here is a filter I wrote*, it is honest and useful. Presented as *here is my collection*, it is a bug report waiting to be filed.

**Favourite sources is the odd one out**, and it points at something worth building. A collection of *sources* rather than of articles costs a handful of canonical URLs, ships nothing of anybody's writing, and leaves every device collecting on its own behalf, which is the first sentence of section 8. It is a shared OPML that stays live, and for a feed reader it may well be the collaboration people actually want. It is one small record type away once the pipe exists, and it belongs on the list rather than never.

## The shape

Three constraints decide the zone, and there is not much freedom left afterwards.

A `CKShare` reaches records in **one zone** only. A zone holds at most **one** zone-wide share. And the existing `Flong` zone must **never** be shared, since it holds every feed, every mark, every read state and the whole stream, and sharing it would hand all of it over in one gesture.

So : **one custom zone per shared collection**, in the owner's private database, and a zone-wide share on it. Zone-wide rather than hierarchical because a hierarchy means a parent reference on every record and a fix-up on every insertion, for a structure that is flat anyway.

What goes in the zone is decided by the size of an excerpt. Three hundred characters of plain text, with a title, a truncated link, a date, a byline and the address of a picture, is under a kilobyte ; two hundred articles is a hundred and sixty kilobytes, which fits inside a single record of about a megabyte with room to spare, and compresses to a fifth of that. **So there is no reason to write one record per article**, which is what the previous draft of this note proposed when a body was travelling and what the whole of section 7 exists to avoid.

| Record type | One per | Carries |
| ----------- | ------- | ------- |
| `SharedCollection` | zone | the name, a word about it, when it was made |
| `SharedList` | participant, chunked | everything that person filed : per article, its title, its truncated link, its date, its byline, its excerpt, the address of its picture, and the name of the source |
| `cloudkit.share` | zone | the participants and their permissions. CloudKit writes it, we do not |

**One writer per record, which is a shape this project already uses.** Section 7 says it of the stream archives : *file synchronization goes wrong when two devices write one file and somebody has to resolve a conflict nobody can resolve correctly*, so each device writes only inside a folder of its own. The same argument holds here with participants in the place of devices. Each person writes their own list and reads everybody else's, two people filing at once cannot collide, and there is no conflict resolution to write. Taking an article back out is a rewrite of your own list, and a rewrite of a record one person owns is not a lost update.

It follows that **you can take back what you put in, and not what somebody else did**. That is a defensible rule and it should be stated rather than discovered. If the owner needs more than that, the shape that keeps the property is a list of their own saying what they have taken down, which merges the same way ; that is a decision below, not a foregone conclusion.

**Chunked when it grows**, numbered from zero, exactly as `StreamBlock` cuts a busy day into as many records as its bytes need. It will rarely trigger : a thousand excerpts still fits.

Locally, two tables : one for the shared collections this device knows about, whether the reader owns them or was invited, and one for the entries in them. **The shared entry never enters `entry`.** More on that below, because it is the mistake that would be easiest to make and worst to unmake.

## Writing from the start

**Decided : a participant may file, from the first version.** Reading somebody else's collection is a document ; filing into it is the collaboration, and shipping the first without the second would be shipping the part that was not asked for.

**It settles nothing about the shape, because the shape was already chosen for it.** One list per participant, each person writing only their own, is what makes two people filing at the same moment a non-event : there is no shared record for them to collide on and no merge to get wrong. Had this been read-only first, the temptation would have been one list for the whole collection, and adding write access later would have meant rewriting it.

**It obliges three things on day one.** Attribution, since a collection several people fill has to say who filed what : `CKRecord.creatorUserRecordID` answers it for free and `CKShare.Participant` turns it into a name. The sentence about participation having a name on it, said before the first share rather than added later. And the second engine has to **send** as well as fetch, since a participant's saves go out through `sharedCloudDatabase` into somebody else's zone, which is a path the private engine never exercises.

**Write access is still per participant, not per share.** `CKShare.ParticipantPermission` is set person by person in the system's own manage-share sheet, and the owner may well invite somebody read-only. So a device holding a read-only participation offers no way to file, and a save that goes out anyway is refused with `permissionFailure` and handled rather than logged and forgotten.

**And each device removes its own secrets.** When somebody files an article from a feed only they are subscribed to, it is their device that truncates the address, against their own keychain, because nobody else can know which of those parameters were theirs. The rule of the previous section is not the owner's to apply on everyone's behalf : it belongs to whichever device is doing the writing.

## Addresses, and the parameters on them

This is where the credential rule has actual work to do, and it turns out to be worth doing whether anything is ever shared or not.

**The feed's own address is already safe.** `MaskedURL` exists for exactly this : a feed whose URL is a secret is written to the database as its origin plus a one-way digest, and the real address lives only in the keychain. There is no path from a record to a secret feed address because there is no path from the *database* to one.

**The article's address is not.** `entry.url` is stored exactly as the feed published it, at `FeedRefresh.swift:318`, and `ArticleKey.tracking` is consulted only to work out whether two articles are the same article, never to clean what is written down. A paper that puts a per-subscriber token on the links inside its feed has that token in the database today, and it would go out in a shared list unless something takes it off.

So **a link is truncated of the parameters that are secret before it travels**, and so is the address of any picture, which can carry the same token. What is left is the public page, which is the thing worth sharing anyway.

**Nothing is cut on a guess.** The tempting rule is that anything on a link from an authenticated feed goes, on the grounds that a session token and a page number look alike. This project has already written down why that is wrong : `docs/technical/feed-identity.md` keeps the query string in a canonical address because *`?format=rss` selects the feed on plenty of sites*. A parameter is as likely to be the identity of the feed, or a filter the reader chose, as a secret, and a heuristic that removes it either collapses two subscriptions into one or hands somebody a link to the wrong page. Flong cannot tell the difference by looking, so it does not try.

**Only what the reader designated goes**, per feed and by parameter name, said in the interface, against a real address so it is plain what is being taken off.

**The designation lives in the keychain, and the keychain is already the right one.** `CredentialStore` writes with `kSecAttrSynchronizable` set to true and `kSecAttrAccessibleAfterFirstUnlock`, under a comment that says why : *carried to the reader's other devices by iCloud Keychain, which is end-to-end encrypted and is not this application's to reinvent.* So a parameter marked as secret follows the iCloud user to their other devices on its own, and a second device that learns of the subscription through CloudKit finds the secret waiting rather than asking for it again. This is another case of `FeedCredential`, in the store that exists, and not a new place to keep a secret.

**Nothing is cut at ingestion.** `entry.url` is written exactly as the feed published it, and it stays that way : the reader has to be able to open the article, and the parameters that are not secret are often what makes the address work at all. The removal happens where an address leaves, which is a shared list, an export, or anything else handed outward.

That leaves one gap, and it should be named rather than discovered : **a reader who has designated nothing has nothing removed.** So the interface asks at the moment it can tell there is something to ask about, which is subscribing to a feed whose address carries parameters, and it asks by showing them rather than in the abstract. Asking is not guessing.

One constraint to keep in view when this is built. An article's link may be truncated freely, since `ArticleKey` decides what makes two articles the same and already drops the tracking parameters. A **feed's** address may not : it is the feed's identity, and `MaskedURL` exists precisely so that two subscriptions to one platform with different secrets stay two subscriptions. Whatever the designation does to what is displayed and to what is exported, it must not quietly make two feeds one.

None of this needs sharing to be useful. A reader who can see and mask the parameters on their own subscriptions is better off today, and the whole of it can ship before a single share is created.

## What must not go wrong

**A credential never travels, in any of its forms.** A cookie session is not sent. A Basic password, a bearer token and a fixed header live in the keychain and there is no path from a keychain item to a record, which is already true and must stay true. A secret feed address is already unreachable through `MaskedURL`. A secret parameter on an article link is truncated out of it, and that one has to be built.

**Text from another person is untrusted, even when it is only text.** This was the largest surface in the previous draft and the excerpt rule has almost closed it : `HTMLSanitizer.excerpt` produces plain text through `plainText` and cuts it at three hundred characters, so **no markup travels at all** and there is nothing for a web view to interpret. What remains is worth doing anyway, because a participant runs their own copy of a client on their own machine and can put whatever they like in a record : cap what arrives at the length an excerpt is supposed to be, refuse control characters and direction overrides, and render it as text and never as markup. Cheap, and the day somebody sends a megabyte of it, it is the difference between a shrug and a hang.

**A shared entry is not the reader's article.** It came from a feed they do not follow. It must not enter `entry`, must not be counted unread, must not be swept up by a purge or a rule or a replay, must not be re-shared onwards, and must not slide into their own collections by accident. A separate table is not tidiness, it is the only way any of that stays true. Where the reader *does* already hold the piece, because they follow the same source, `ArticleKey` already answers whether two articles are the same article : the shared collection should then show *their* copy, with their read state and their marks, and the sender's excerpt only where they have none. And the honest way to keep a shared article is the explicit one : subscribe to its source.

**Participation has a name on it.** Being in a share tells the other participants who you are, by the name on your iCloud account, and `CKRecord.creatorUserRecordID` says which of them filed what. For an application whose whole story is that it has no account and knows nobody, that is a genuine change in what the reader is agreeing to, and the interface should say it before the first share rather than after.

## What it costs

**A handful of records per shared collection** : one `SharedCollection`, one `SharedList` per participant, one share. Against the three thousand of section 7, sharing twenty collections is unremarkable. The previous draft put one collection at two hundred records and a visible fraction of the whole budget ; that difference is the excerpt rule paying for itself.

Records a participant writes count against **the owner's** iCloud storage, not their own. At this size it is kilobytes and nobody will notice, which is worth saying only because it would not have been true of bodies.

No `CKAsset` and no size escape hatch, since nothing approaches the record limit. **No picture bytes either** : the address travels and each device fetches the image itself, the same request any web page would make, against a link truncated like every other.

**The archives stay out of it.** A shared collection is small and wants to arrive promptly, which is exactly the trade section 7 makes when it says records carry the near end and archives carry the bulk.

## What has to change in the code that exists

More than a bolt-on, and worth knowing before starting.

**`CloudSync` assumes one zone, everywhere.** `zoneID` is a stored property and `recordID(for:)` builds every identifier in it, so every save, every deletion and every fetch is scoped to `Flong` by construction. The owner's shared-collection zones live in the same private database, so the private engine has to carry several zones rather than one.

**`sync_record` has no zone.** It is keyed by record name alone, which was right while there was one zone and is not once there are many. Record names are digests and globally unique, so nothing is ambiguous, but the zone has to be stored to build the identifier again. That is a migration.

**`SyncPayload` answers by name, from one zone**, both when it is asked what to send and when it applies what arrived. The shared zones need their own path through both, and it should be a separate one : what arrives from a participant is subject to the caps and the isolation above, and routing it through the same code as a record from the reader's own device is how those get skipped.

**A second engine, on `sharedCloudDatabase`**, with its own serialized state and its own delegate path, for collections the reader was invited to.

**Two delegates**, one per platform, for `userDidAcceptCloudKitShareWith` and nothing else.

**The production schema.** `docs/technical/sync.md` already carries the warning and this adds to it : two new record types and the share, deployed from the CloudKit console before any build leaves this machine, and again the next time a field is added.

**Testing.** `CloudSync` is described in its own header as the one file that cannot be tested from the outside, and sharing makes that worse : it wants two accounts and two devices. So the parts that can be tested must be, and they are the parts that matter : the encoding and decoding of a `SharedList`, the truncation of a link and of a picture's address, the caps on what arrives, and the identity match against a local article. The share flow itself is verified by hand.

## What I would build, in what order

1. **Amend section 2**, and add a section on collaboration to the specification. First, because everything after it is a change to a document that currently forbids it.
2. **The parameters on an address**, with the interface for saying which are secret and the asking at subscription time. It stands alone, it needs no share to be worth having, and it is the piece every later step depends on for not leaking a credential.
3. **Several zones in the private engine.** No user-visible change at all, and the migration and the surgery on `CloudSync` and `SyncPayload` land on their own where they can be reviewed as what they are.
4. **The made collection, read and write.** Zone, share, `ShareLink`, the two delegates, acceptance, the second engine sending as well as fetching, the excerpts travelling both ways, the shared entries in their own table, matched against local copies where there are any, and who filed what shown on each. This is the feature, and the dynamic collection comes with it for one record more. Reading lands before writing inside this step, since there is no way to test a save without somewhere to see it arrive, but the step is not finished until a participant can file.
5. **The shared source list**, which is one small record type on a pipe that by then exists.

## What I need decided

- **The non-goal.** Section 2 forbids this in writing. Amending it is the first commit or there is no second one.
- **Whether the owner may take down somebody else's entry.** No is the simple rule and one writer per record gives it for free : you take back what you put in, and nothing else. Yes needs a list of their own saying what they have taken down, which merges the same way and is not much more. Now that writing is in from the start, this is the last question the shape depends on.
