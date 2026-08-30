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

Every refresh asks the keychain for the real address. A keychain that will not answer means the feed is fetched without its credential, the server answers 401, and section 9 quarantines it — which is a better outcome than refusing to try, and one the reader can see and act on.

## What is never shown

A credential's own description of itself never contains the credential : `Secret address`, `Signed in as alice`, `Bearer token`, `Header X-Auth`. A name is not a secret, and saying it is what makes an entry legible ; a token is, and never appears.

That is a tested property rather than a convention, since it is the kind of thing that decays quietly.

## Sessions on sites the reader pays for

Everything above is about a **feed** that is paid for. The other case is a public feed whose articles sit behind a wall : the reader subscribes to the newspaper, and the extraction of `docs/technical/extraction.md` comes back with a teaser.

Section 9 used to put this out of scope, and the reason it gave still holds : a login form is not an interface anybody promised to keep, and a session breaks when the site decides it does. The section is amended rather than quietly contradicted, and the cost is made legible rather than hidden.

**The reader signs in on the site's own page**, in a web view, and what is kept is the cookies that page left behind. Flong never holds a password, never fills in a form, never automates a sign-in. That is a limit and not a shortcut : a program that fills in login forms is a program that has to be told a password, and this way there is nothing to be trusted with.

The web view runs scripts, which is the one place in the application that does. A login form is a real page on a real site and does not work without them ; the view an article is read in is a document Flong built itself and has no business running anything. The two are opposite cases and are configured opposite ways. It also uses a data store of its own, thrown away with the sheet : what is kept is kept deliberately, in the keychain, and the rest goes.

**A session goes to its own site and nowhere else.** `lemonde.fr` covers `www.lemonde.fr` and `secure.lemonde.fr` ; it does not cover `notlemonde.fr`, and the dot is what tells the two apart. Getting that wrong would send a subscription's cookies to whoever registered the lookalike, so it is a tested property rather than a careful line of code. The cookies of the third parties a login page loads are dropped on the way in : what an advertiser left has nothing to do with the reader being a subscriber.

The cookies are set on the request rather than left to a shared cookie store, which is what makes that scoping something the code does rather than something it hopes for.

**When it breaks, it says so.** A session records when it was signed in and, separately, when a page last came back whole — which is the only honest proof it still works. A fresh sign-in has proved nothing yet and does not claim to. A site that has started refusing shows as signed out rather than as articles that mysteriously went back to being teasers.
