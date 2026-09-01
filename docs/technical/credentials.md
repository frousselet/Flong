# Private and authenticated feeds

Section 9 of the specification names four ways a subscription proves the reader is entitled to it, and they are the four that keep working.

| Kind | What it is | Who uses it |
| ---- | ---------- | ----------- |
| Secret address | The address itself is the secret | Substack, Ghost, Patreon, most subscription platforms |
| HTTP Basic | A name and a password | Self-hosted feeds, some newsletters |
| Bearer token | `Authorization: Bearer …` | Platforms with an API |
| Fixed header | A header a platform names itself | The ones that invented their own scheme |

## Where they live

The keychain, exclusively. Never the database, never CloudKit, never a log, never an error message, never a default export.

**Synchronizable**, so a reader who paid once does not sign in again on their iPad. iCloud Keychain is Apple's own end-to-end encrypted channel, which is a better place for a password than anything this application could build.

**`afterFirstUnlock`**, which is the class the database is under and for the same reason : a feed refreshed by a background task at four in the morning needs its credential. `whenUnlocked` would be stricter and would stop background refresh working for exactly the feeds a reader pays for.

They are keyed by the feed's identifier, which is a UUIDv7 and not a secret. That works for all four kinds, and it means a credential survives a feed being renamed or moved.

## The problem a secret address poses

A feed is identified by its canonical URL, and a feed whose URL is a secret cannot be identified by something the database is not allowed to hold.

So the database holds a **masked** address : the origin the reader recognizes, and a digest of the real one in place of the part that must not be written down.

```
real     https://rss.example.com/u/9f3c2a11d4e5/feed.xml   → keychain
database https://rss.example.com/private/a3f9c2b1e4d7a8f0
```

It is a URL like any other, so `FeedURL.canonical` and everything built on it work unchanged. It is unique per secret address, so two subscriptions to one platform stay two subscriptions. It is stable, so a feed does not become a second feed on the next launch. And it is one way : the digest gives nothing back.

Every refresh asks the keychain for the real address. A keychain that will not answer means the feed is fetched without its credential, the server answers 401, and section 9 quarantines it, which is a better outcome than refusing to try, and one the reader can see and act on.

**It is shown hidden rather than not shown**, in the editor of its own source and nowhere else : read back from the keychain into the same field as any other address, drawn as dots, and read out on a deliberate tap. The rule it obeys is the one section 9 states, masked in the interface, and dots are masked. What it cannot be is unreachable. A platform that reissues a token, a subscription that moves host, a parameter the reader has to add by hand : none of those had any repair at all while the only thing the screen would show was a digest, and the reader could not so much as check the address against the platform's own page.

**Whether an address is a secret can be changed afterwards**, and it had to be. A reader who pastes a per-subscriber address without saying it is one had no way back : the address sat in the database in clear, and in the subscription record of their own iCloud, and the only repair was to stop following the source. The switch is in the editor of the source, in the address section, because it is a fact about the address rather than a setting beside it. Turning it on masks the row and puts the address in the keychain, which also deletes the record the plain address was in ; turning it off writes it back in the open, from the keychain unless the reader types another, and the screen says so before it is asked for. Either way it is a move, so it goes through the one path `docs/technical/editing-a-source.md` describes and keeps every article and every mark.

## The parameters on an address, which the reader designates

A secret does not always take one of the four shapes above. A platform may serve a feed at an ordinary address and put a per-subscriber token in the query string of it, or of every article link inside it. `entry.url` holds an article's address exactly as the publisher spelled it, so such a token is in the database and would go out on any address that leaves the device.

**Flong does not guess which parameter that is, and `SecretParameters` is why it does not have to.** `?token=` and `?format=rss` look exactly alike from here, and `docs/technical/feed-identity.md` already settled the consequence for identity : a canonical address keeps its query string because it *selects the feed on plenty of sites*. A heuristic that stripped it to be safe would collapse two subscriptions into one and hand somebody a link to the wrong page.

So the reader says, per feed and by parameter name, and nothing else is ever taken off. The designation joins the credential in the keychain, under a service of its own since the account is already the feed, which carries it to their other devices through iCloud Keychain and keeps it out of a default export. A feed may have the designation without a credential, and a reset takes both.

**Nothing is taken off at ingestion.** The reader has to be able to open the article, and the parameters that are not secret are frequently what makes the address work at all. `PublicURL` is what an address goes through where it leaves : it takes the designated parameters, the tracking of `ArticleKey.tracking`, which only ever said who sent them, and anything written in front of the host, since a `user:password@host` is a credential in an address without being a parameter at all.

**The question is asked against real addresses**, the real ones. For a secret feed that means the address out of the keychain rather than the masked form the row holds : the masked one carries no parameters at all, so the screen used to tell a reader looking straight at their own token that neither the feed nor its articles had one. `SourceEditor` lists what the feed's address and its recent articles' addresses actually carry, each with its value masked : a list of parameter names in the abstract is a list of things nobody recognizes, and printing the values would make the screen a strange place to keep a secret. It is offered for every feed and not only for the ones that look authenticated, since a plain feed with a token on every link inside it is exactly the case a reader would never think to look for.

It sits in the editor of the source rather than behind a line of its own in the menu, which is where it was. The question it asks is about this source's addresses, the editor is where those addresses are, and a screen a reader has to know exists is a screen most of them never open. `docs/technical/editing-a-source.md` covers the rest of that screen.

**Each device applies its own designations to its own writes.** When somebody files an article into a shared collection, it is their device that truncates the address, against their keychain, because nobody else can know which of those parameters were theirs.

## What is never shown

A credential's own description of itself never contains the credential : `Secret address`, `Signed in as alice`, `Bearer token`, `Header X-Auth`. A name is not a secret, and saying it is what makes an entry legible ; a token is, and never appears.

That is a tested property rather than a convention, since it is the kind of thing that decays quietly.

## Sessions on sites the reader pays for

Everything above is about a **feed** that is paid for. The other case is a public feed whose articles sit behind a wall : the reader subscribes to the newspaper, and the extraction of `docs/technical/extraction.md` comes back with a teaser.

Section 9 used to put this out of scope, and the reason it gave still holds : a login form is not an interface anybody promised to keep, and a session breaks when the site decides it does. The section is amended rather than quietly contradicted, and the cost is made legible rather than hidden.

**The reader signs in on the site's own page**, in a web view, and what is kept is the cookies that page left behind. Flong never holds a password, never fills in a form, never automates a sign-in. That is a limit and not a shortcut : a program that fills in login forms is a program that has to be told a password, and this way there is nothing to be trusted with.

The web view runs scripts, which is the one place in the application that does. A login form is a real page on a real site and does not work without them ; the view an article is read in is a document Flong built itself and has no business running anything. The two are opposite cases and are configured opposite ways. It also uses a data store of its own, thrown away with the sheet : what is kept is kept deliberately, in the keychain, and the rest goes.

**One sign-in covers the whole site.** A reader signs in at `www.lemonde.fr` and wants the session for every feed and article of the paper, `abonnes.lemonde.fr` included. Guessing where a domain ends from the address they happened to use would need the public suffix list and would get `example.co.uk` wrong ; the cookies say it themselves. A site that wants its session to work across its subdomains sets `.lemonde.fr`, and that declaration is the site's own and authoritative. The session is kept under the broadest domain its own cookies claim, and a cookie claiming a domain the reader did not sign in at is a third party and does not get to widen anything.

**A session goes to its own site and nowhere else.** `lemonde.fr` covers `www.lemonde.fr` and `secure.lemonde.fr` ; it does not cover `notlemonde.fr`, and the dot is what tells the two apart. Getting that wrong would send a subscription's cookies to whoever registered the lookalike, so it is a tested property rather than a careful line of code. The cookies of the third parties a login page loads are dropped on the way in : what an advertiser left has nothing to do with the reader being a subscriber.

The cookies are set on the request rather than left to a shared cookie store, which is what makes that scoping something the code does rather than something it hopes for.

**When it breaks, it says so.** A session records when it was signed in and, separately, when a page last came back whole, which is the only honest proof it still works. A fresh sign-in has proved nothing yet and does not claim to. A site that has started refusing shows as signed out rather than as articles that mysteriously went back to being teasers.
