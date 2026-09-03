# Bringing a FreshRSS account over

Section 19 of the specification makes a remote service a **one-shot import source**. This page is what Flong does with the account once it has opened it ; `docs/technical/freshrss-api.md` is the protocol it opens it with, and is the authority for every shape named below.

The surface is the Google Reader compatible API, so the same implementation reads Miniflux, Inoreader, The Old Reader and BazQux. The screen says FreshRSS because that is the word the reader knows.

**Nothing is ever written back.** The API has endpoints for subscribing, unsubscribing, marking read and starring, and none of them is called. Flong reads the account, and afterwards it collects the feeds itself and has no further business with the server. There is no permanent synchronization and there is nothing to turn off later.

## What the reader chooses

One screen, three steps, and nothing is written until the second is over.

1. **Sign in.** The address of the instance, the username, and the **API password**, which is the one FreshRSS asks for under Profile and not the one the site is signed in to with. The screen says so, because nothing else will and it is the one thing everybody gets wrong.
2. **Choose.** Every subscription of the account, ticked by default, with the ones this device already follows marked as such. Beside them : whether to bring the articles, how much of each source's history, and whether to bring the favourites.
3. **Watch it arrive.**

Whatever is ticked is written down before the first article is fetched, so an import finished tomorrow brings what was chosen today rather than what the account holds tomorrow.

### The address, however it is spelled

FreshRSS puts its interface at `…/p/i/` and its API at `…/p/api/greader.php`, so what a reader pastes out of their browser is almost never the API's own address. `GoogleReader.base(of:)` resolves every spelling to the same place : a trailing script name goes, then `api`, then `i`, and `api/greader.php` is added back. An installation under a path keeps it, because `/FreshRSS/p/` is where somebody chose to put it and is not guessable.

### How much history

The reader picks, in articles per source : a hundred, five hundred, or everything.

**A bound rather than everything by default**, and the unit is deliberately articles rather than days. An instance that has been collecting for five years can hold more than the whole budget of section 21 allows this store, and a month of a daily paper and a month of a weekly are not the same amount of anything. Articles per source is what the API pages in and the only unit that bounds the work predictably.

The stream is not purged unless the reader asked for it to be, so what an import brings stays. A reader who has asked for a bounded store is asking for the opposite of a deep import, and gets what they asked for at the next purge.

## The three passes

Each is resumable on its own, and they run in this order for a reason.

| Pass | What it does | Where it resumes from |
| ---- | ------------ | --------------------- |
| Subscriptions | Follows what was ticked, in one transaction | Done or not done |
| Articles | Walks each chosen source's stream, newest first | The continuation token, per source |
| Favourites | Walks the starred stream, which spans every source | The continuation token |

The subscriptions come first because everything else needs a row to hang off. The favourites come last because a favourite belongs to a feed, and which feeds this device follows is settled by then.

**A merge, never an overwrite.** A source already followed keeps the name, the refresh interval and everything else the reader decided about it : `SubscriptionStore` only ever fills in what is still empty, which is the same rule an OPML import obeys. `docs/technical/feed-identity.md` is what decides two spellings of one address are one source.

**Folders are read and not kept**, as an OPML file's tree is not. A source belongs to the publisher serving it, which its own address already says.

## Writing an article down

An imported article goes through `FeedRefresh.store`, the same write a refresh does. That is deliberate : a second copy of that rule would be a second opinion about what a duplicate is, how a byline is spelled and which picture stands for a piece.

### The identity is a considered guess

The API serves **the service's own numeric identifier** and never the GUID the feed stated, so there is nothing to carry across. What is stored instead is the address the article lives at, because a permalink is what the great majority of feeds put in their `guid`. Guessing it means the same article fetched from the publisher tomorrow lands in the row imported today, wearing the read state and the star the account held for it.

**Where the guess misses, nothing breaks.** The canonical key is computed from the same address by the same rule, so the copy arriving from the publisher recognizes the imported one, points at it and is shown nowhere. The reader sees one article either way. See `docs/technical/ingestion.md` and `ArticleKey`.

### Read and starred are a union

Read state and stars are derived from the `categories` array of each article and from nowhere else. They are applied **on top** of the write, and only ever widen :

- read here and unread there stays read ;
- starred here and unstarred there stays starred.

The account is one more thing with an opinion about an article, not the authority on it. An import that could mark a hundred read articles unread is an import nobody dares run twice, and it is the rule section 7 already applies between the reader's own devices.

### A favourite of a source nobody took

A starred article belongs to a feed, and a source the reader unticked is a source there is no row to hang one off. Those are counted and reported, never guessed into a subscription nobody asked for. It is the rule `StreamBlock` already applies to what another device sends.

## Being interrupted

An account of sixty feeds and thirty thousand articles is minutes of network. A phone locked halfway through is the ordinary case, not the exception.

**The resume point is written down.** `import_job` holds the account, what was chosen, and where the starred stream got to ; `import_source` holds every subscription the picker listed, ticked or not, with the continuation token of its own stream. Both are written after every page. Resuming asks for the page after rather than the first page again.

**Everything is idempotent anyway.** A subscription is matched by its canonical address and an article by its identity within its feed, so running the whole import twice adds nothing the second time. That is what makes resuming safe even where the page it resumes from has already landed.

**One import at a time.** Starting one replaces whatever was there. Two accounts being imported at once is not a thing anybody asked for.

**One runner.** The screen and the background task both call the same method, and a caller arriving while a run is going waits for it rather than starting a second walk through the same streams.

### The API password

In the keychain, keyed by the job's identifier, exactly as a feed's credential is keyed by the feed's. `docs/technical/credentials.md` states the rule and an API password is a password whatever it opens. It is deleted the moment the import ends, whether it ran to the end or the reader gave up on it.

It is what lets a resumption open a session again without asking the reader for anything. The token the server hands out would do as well and is not kept : signing in again is one request.

### Carrying on in the background

The import asks the system for a `BGContinuedProcessingTask` when it starts. Where the system takes it, the reader may leave : the work carries on, the system draws its own progress, and the handler re-enters and either waits on the run already going or carries the written-down import further.

**A refusal is not a failure.** Section 15 says this API is not to be relied on. Where the system says no, the screen holds the reader instead : the bar takes the whole screen and asks them to stay until it is over, because leaving really would stop it. Either way the resume point is on disk and nothing is lost.

**Offered rather than resumed on its own.** An import found unfinished at the next launch is not started : it is minutes of network, and an application that helped itself to that over cellular is an application nobody trusts with their data allowance. The offer stands in the sources panel, beside the other things a reader has to act on.

## What is deliberately not here yet

- **Miniflux, Feedbin and Feedly by name.** Miniflux serves this same API and should work as it stands ; Feedbin and Feedly have their own and are section 19's remaining work.
- **Query translation** from the FreshRSS syntax, which section 19 asks for with an explicit report of what could not be translated. `FreshRSSSyntax` already translates the search syntax at parse time ; the saved queries of an account are not read.
- **Article labels.** `tag/list` tells a label from a folder, and a label is something the reader said about an article and does travel. It is not read yet.
