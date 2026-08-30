# Marks

There is one notion of an article and no second copy of anything. What the reader says about one - starred, written on, filed in a collection - is a **mark**, carried on the article's own row, and it is the whole of what distinguishes an article they kept from one that merely arrived.

## What the library was, and why it went

An article used to enter a library by being starred or annotated, and at that moment everything it needed to be read again was copied into a second table : title, text, author, language, address, and the name and address of its feed. Nothing pointed at the stream row, deliberately, because that row was a cache that would be purged.

Four guarantees paid for that copy, and three of them went away one at a time :

| The copy guaranteed | What happened to it |
| ------------------- | ------------------- |
| it survived the purge of the stream | nothing is purged now unless the reader asks, and a marked article is spared even then |
| it survived the article vanishing from the web | the stream keeps the text and travels with it, so every device has it |
| it survived a device being set up fresh | the stream travels whole, so it arrives with everything else |
| it froze the version read | genuinely lost : a publisher's later edit now reaches the article |

The fourth is the only real cost, and it did not justify a second store on its own. What the copy still held, once the frozen text stopped being wanted, was the reader's own marks, and those belonged on the article all along.

**The bugs it cost while it existed are the honest argument.** Two stores meant two identities for one article, and the interface had to know which one it was holding. A star pressed on a kept copy addressed the copy ; unstarring threw the copy away and every collection it was in emptied with it. A count said two and the page showed one, because `tag_binding` carries no foreign key and a discarded copy left its bindings dangling. None of those are possible now : there is one row, and a mark is a column on it.

## What a mark is

| Part | Where it lives | Way in | Way out |
| ---- | -------------- | ------ | ------- |
| starred | `entry.is_starred` | the star | the star again |
| annotation | `entry.annotation` | writing a note | emptying it, which is no note at all |
| collections | `tag_binding` under the `collection/` root | filing it | unfiling it |
| vector | `entry.vector`, with its model and revision | the vectorizer | a model revision this device does not run |

The three ways of marking are independent. Unstarring an article somebody wrote a note on keeps the note ; unstarring one that is filed leaves it filed. Throwing away what a reader wrote is the one unforgivable thing a reader application can do, and the same reasoning covers a filing.

## The purge never takes a marked article

Retention bounds the store by age and by volume, and is asked for rather than scheduled. Both passes exclude the same three conditions, written once as `Retention.marked` : starred, annotated, or bound to a collection. A purge sparing only the stars would throw away the article somebody wrote three paragraphs on, which is exactly the article they would most want back.

## Between devices

**One record per marked article**, named after the pair of feed address and article identity, so two devices marking the same article compute the same name and write one record between them.

Not compacted into a block per month, which is the shape read states take and the shape this was first written as. The reasoning is in `docs/technical/sync.md` and in section 7 of the specification : reading happens once and never unhappens, so a union is right for it and is commutative ; a mark comes off again, and in a block the last device to write a month would win the whole month.

An article unmarked entirely has nothing left to say, and its record is deleted. **The deletion is what carries the `no`.**

**A mark may arrive before its article.** CloudKit hands its batches over in whatever order it likes, and a star may well land before the article it is about. It waits in `pending_mark` and is written the moment the article turns up, from iCloud or from its own feed. Dropping it would lose it for good, since nothing re-sends a record that was already delivered.

## Spotlight

Section 11 gives Spotlight the marked articles and only those : a few thousand items, which is what it is good at, against the hundreds of thousands of the whole stream, which it is not. An article is offered because the reader did something to it ; everything else is a cache nobody chose, and a system-wide index of a cache is an index of things nobody asked for.

- **A named index, not the shared one.** Only a named index supports batching and the client state, and the shared one throws `Batching not supported` at the first call, as an Objective-C exception no Swift `catch` can stop. A named index is still the application's Spotlight index and what goes into it turns up in the system search exactly the same.
- **Spotlight keeps the record of what it holds.** The client state is stored by Spotlight, not by Flong : if Spotlight loses its index, it loses the state with it, the next check sees a mismatch, and everything is written again. An application that remembered the state itself would confidently skip the rebuild it most needed. That is also why `CSIndexExtensionRequestHandler`, which section 11 mentions, is not needed to stay correct : it would let Spotlight schedule the rebuild at a better moment, and it can be added as an extension target when that moment matters.
- **The whole text goes to `textContent`.** `contentDescription` is capped around three hundred characters ; `textContent` is what Spotlight actually searches through. Fetching the page rewrites the plain text with it, so an article read whole is searched whole rather than by its teaser.
- **Nothing expires.** A marked article is never purged, so neither is its index.
- **The domain is still called `library`.** It is an opaque identifier the system keys its own records on, and renaming it would abandon what is already indexed rather than replace it.
- Opening a Spotlight result opens that article in Flong.

The index is local to the device and never shared between the devices of one account. Each of them indexes for itself, as section 11 sets out.

## Searching

There is one corpus and one full-text index over it, described in `docs/technical/search.md`. `is:starred`, `is:annotated` and `is:collected` narrow a search to what the reader marked, and the semantic half is what Spotlight and the vectors are for.
