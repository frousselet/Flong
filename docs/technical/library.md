# The library

The stream is a cache and the library is not. That distinction is the product, and it is worth being exact about what it means in the store.

## What promotion copies

An article enters the library by being starred or annotated, and at that moment everything it needs to be read again is **copied** : its title, its text, its author, its language, its address, and the name and address of the feed it came from.

Nothing points at the stream row for content. That row is a cache and will be purged, the feed can be unsubscribed from, and the article can vanish from the web in a year. A library item that needed any of the three would be a library item that stops working, which is the one thing the library exists not to do. Two tests hold it : one deletes the article under a kept copy, the other unsubscribes from its feed.

The copy is never refreshed afterwards. A kept article says what it said on the day it was kept, and a publisher's later edit does not reach into somebody's library.

## What keeps an article

| Way in | Way out |
| ------ | ------- |
| starring | unstarring, unless something else still keeps it |
| annotating | removing the annotation, or removing the item |
| a rule (M5) | the rule no longer applying, or removing the item |

Starring and keeping happen in one transaction : an article starred and not kept, or kept and not starred, is a state nothing in the interface could explain. Removing a kept article unstars its stream row with it, so the two always agree.

**An annotation outlives a star.** Unstarring an article somebody wrote a note on keeps the note, since throwing away what a reader wrote is the one unforgivable thing a reader application can do.

Promotion is idempotent. An article kept twice is kept once, whether it arrives twice by two paths or twice from two spellings of the same feed.

## The purge never applies

Retention bounds the stream, by age and by volume, and has no reason to touch the library table at all. A starred stream row is spared too, so what the reader kept stays visible where they kept it as well as in the library.

## Spotlight

Section 11 gives Spotlight the library and only the library : a few thousand items, which is what it is good at, against the hundred and twenty five thousand of the stream, which it is not. Two things come of it at once. What the reader kept turns up in the system search, and Spotlight's semantic matching is had for nothing.

- **A named index, not the shared one.** Only a named index supports batching and the client state, and the shared one throws `Batching not supported` at the first call, as an Objective-C exception no Swift `catch` can stop. A named index is still the application's Spotlight index and what goes into it turns up in the system search exactly the same.
- **Spotlight keeps the record of what it holds.** The client state is stored by Spotlight, not by Flong : if Spotlight loses its index, it loses the state with it, the next check sees a mismatch, and everything is written again. An application that remembered the state itself would confidently skip the rebuild it most needed. That is also why `CSIndexExtensionRequestHandler`, which section 11 mentions, is not needed to stay correct : it would let Spotlight schedule the rebuild at a better moment, and it can be added as an extension target when that moment matters.
- **The whole text goes to `textContent`.** `contentDescription` is capped around three hundred characters ; `textContent` is what Spotlight actually searches through.
- **Nothing expires.** The library is never purged, so neither is its index.
- Opening a Spotlight result opens that article in Flong.

The index is local to the device and never shared between the devices of one account. Each of them indexes for itself, as section 11 sets out.

## Searching the library

The stream has its own index and its own language, described in `docs/technical/search.md`. The library is a few thousand items, so a plain match over what was kept answers it directly, and the semantic half is what Spotlight is for.
