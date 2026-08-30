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
