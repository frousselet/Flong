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

Section 11 gives Spotlight what the reader chose and only that : a few thousand items, which is what it is good at, against the hundreds of thousands of the whole stream, which it is not. Two things go in, and each of them is chosen rather than collected.

### The articles

Five ways of choosing one, written once as `ArticleStore.wasChosen(_:)` and used by every query that asks the question.

| Choosing | Made | About |
| -------- | ---- | ----- |
| a star | one article at a time | the article |
| a note | one article at a time | the article |
| a filing in a collection | one article at a time | the article |
| a favourite source | once, for everything that follows | the publisher |
| a favourite author | once, for everything that follows | the writer |

The last two are deliberately wider than `Retention.marked`, which is what a purge may not take. A favourite is a judgement about a source or a writer rather than about an article, so it earns an article a place in the system search without earning it a place a purge has to work around. A reader who singles out a prolific publisher is the one case that can push the index past a few thousand items.

Everything outside those five is a cache nobody chose, and a system-wide index of a cache is an index of things nobody asked for.

### The stories

The stories on the front page, no more and no less : the same list, from the same read, that `docs/technical/digest.md` describes. A story is where the digest starts and it is what a reader watching a subject is actually looking for, so the system search has to be able to find one.

- **A domain of their own**, `stories`. That is what makes `no more and no less` cheap : the page is written by emptying that domain and writing it again, which needs no record of what was there before and cannot leave behind a story that has left the page.
- **The front page, never a narrowed one.** Narrowing the digest to one subject is a question about the window the reader is looking at, not about what the system search should be able to find.
- **Written when the page changes, and not when the store does.** The digest is read back on every change the store notices, and almost none of those changes are the page : an article marked read is a reason to read the digest again and no reason at all to write sixty items to the system index.
- **They expire when they would leave the page.** A story is on the front page while its last article is inside the digest's window, so the item carries exactly that moment as its expiry. That is what holds `no more and no less` true on a device that was put down for a week.
- **No `contentURL`.** A story is several articles from several rooms, so it is not a page on anybody's site and must not pretend to be one.

### How it stays in step

- **A named index, not the shared one.** Only a named index supports batching and the client state, and the shared one throws `Batching not supported` at the first call, as an Objective-C exception no Swift `catch` can stop. A named index is still the application's Spotlight index and what goes into it turns up in the system search exactly the same.
- **Spotlight keeps the record of what it holds.** The client state is stored by Spotlight, not by Flong : if Spotlight loses its index, it loses the state with it, the next check sees a mismatch, and everything is written again. An application that remembered the state itself would confidently skip the rebuild it most needed. That is also why `CSIndexExtensionRequestHandler`, which section 11 mentions, is not needed to stay correct : it would let Spotlight schedule the rebuild at a better moment, and it can be added as an extension target when that moment matters.
- **The state is a SHA-256 digest and not a hash.** `Hasher` is seeded afresh in every process, so the same articles hashed at two launches gave two different answers and the check never once said `nothing has changed` : the whole index was written again at every launch, which is precisely the work the client state exists to avoid.
- **Deciding is cheap, deciding yes is not.** The question is asked of the chosen articles' identifiers and dates alone ; only a mismatch reads their full texts. It is asked after every catch-up that brought something, since an article from a favourite source or a favourite writer is chosen the moment it lands without the reader touching it, and again whenever a favourite is made or undone, since one decision about a source turns into thousands of articles found or no longer found.
- **The whole text goes to `textContent`.** `contentDescription` is capped around three hundred characters ; `textContent` is what Spotlight actually searches through. Fetching the page rewrites the plain text with it, so an article read whole is searched whole rather than by its teaser.
- **A chosen article never expires.** It is never purged, so neither is its index. A story does, as above.
- **The article domain is still called `library`.** It is an opaque identifier the system keys its own records on, and renaming it would abandon what is already indexed rather than replace it. An article's item identifier is the bare UUID for the same reason : only the stories carry a `story/` prefix, so nothing already indexed is orphaned by them arriving beside it.
- Opening a Spotlight result opens what it stands for : an article is read over everything, a story is pushed as a page in the digest.

The index is local to the device and never shared between the devices of one account. Each of them indexes for itself, as section 11 sets out.

## Searching

There is one corpus and one full-text index over it, described in `docs/technical/search.md`. `is:starred`, `is:annotated` and `is:collected` narrow a search to what the reader marked, and the semantic half is what Spotlight and the vectors are for.
