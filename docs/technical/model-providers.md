# The reader's own model providers

Which model answers each of the four things a model does in Flong, and what it takes for that to be a model the reader brought rather than the one on the device.

Section 14 of the specification carries the decision. This page carries the design : what is configured, where the key lives, what leaves the device and what never does, what is written down about each call, and what the reader is asked before any of it happens.

## What it costs the specification, before anything else

Section 1 says *enrichment entirely on device : classification, tagging and summaries by the system model, without any content leaving the device*, and section 20 enumerates what leaves the device and does not include this. A model of the reader's own contradicts both of those sentences, so it amends them in the same commit or the reference stops being one. `docs/technical/popular-feeds.md` made the same argument for the pool and the shape of the answer is the same.

**What does not change**, and it is most of it. There is still no server of ours, no account of ours and no backend service : the call goes from the reader's device to the host they named, with credentials they hold, and none of it reaches us. Section 2 keeps *depend on no third-party service to function*, and that is what makes the rest possible : Flong ships with the model on the device and nothing else, every screen works with no provider at all, and the path with no model is still the tested one that section 22 makes blocking.

**What changes** is one sentence and it is a real change : a reader who has an account somewhere may point one of the four things a model does here at it, and the headlines and standfirsts of the articles on their front page then leave their device.

**Nothing is sent before they have been asked.** The question is asked once, names what leaves and the host it goes to, and is refused by default. Withdrawing it puts every task back on the device and keeps the accounts.

**And every call is written down here**, on the device : the task, the host, the model, how much went and what came back. Never the prompt, never the articles, never the key.

## The four things, and why they are four

| Task | What it does | What it is worth to a reader |
| ---- | ------------ | ---------------------------- |
| `headlines` | The headline of a story and the line under it | The heaviest : up to four turns, one conversation per story |
| `subjects` | Which of the reader's own subjects a story falls under | One turn per story, against a list it must choose from |
| `editions` | The two or three points over a whole front page | One turn for the whole page, and the cheapest of the four |
| `search` | What a sentence typed into the search field is asking for | The only one somebody is waiting on with their finger still on the key |

They are separate settings because a reader may reasonably want them answered by different models. The sentence they type wants an answer instantly and costs nothing on the device ; the headlines over a night's stories do not, and are where a better model shows.

**A model that fails hands the task back to the device.** Where Apple Intelligence is there it writes instead, and where it is not the path with no model at all is what is left, which is what section 14 has always required. The provider's own row carries the reason, so a key that expired is visible rather than silently costing the reader the better half of their page.

## What is configured

A provider is an account of the reader's, and everything about it that is not a secret lives in the key-value store beside their other decisions : which model answers what, the name they gave it, its origin, the model identifier, the names of any headers they added, and what the server turned out to understand.

**A preference and not a record.** It is a decision about themselves, like the hours their editions come out. The database is stream and library, purged by retention and budgeted against three thousand CloudKit records, and a configuration is neither. It also has to travel, or the feature half-works : with the account in the key-value store and the key in the synchronizable keychain under the same identifier, a second device is configured for free and no secret ever sits in the key-value store.

**Two kinds and not twenty.** Almost every service speaks the OpenAI format, including the servers a reader runs on their own machine ; Anthropic speaks its own. What separates one service from another inside a kind is an address and a model name, and the reader types both.

## Where the key lives

The keychain, exclusively, under a service of its own, keyed by the provider's identifier. Never the database, never the key-value store, never a log, never an error message, never an export.

**`afterFirstUnlock`**, the class the database and the feed credentials are under, and for the same reason : the night's pass writes tomorrow's page while the device is locked, and a key that could not be read then would be a provider that only answers while the reader is watching.

**Synchronizable**, so a reader who typed a key on their phone does not type it again on their iPad. The accounts travel already ; a key that did not would leave the iPad holding a row that looks configured and fails on every call, which is worse than either honest state.

**It is never read back to the screen, and this is a deliberate divergence.** `docs/technical/credentials.md` shows a secret feed address in dots and reads it out on a deliberate tap, and its argument is that the reader must be able to compare it against the platform's own page. That argument does not carry here : a key is minted by the service, shown once by the service, and reissued at will, so there is nothing to compare it against. The row says a key is stored and offers to replace it.

**A base address can itself be a secret**, and a private endpoint with a token in its path is the case. The origin stays in the open, because the consent names the host out loud and the log records it and a promise about where something went that would not name the place is not a promise. Everything after the origin goes to the keychain with the key.

## What a reset takes

The seven places of `docs/technical/erasure.md` are still seven. A provider's key is a keychain entry, so the keychain sweep has a second service to clear ; the accounts and the one consent are preferences, so they go when the key-value store is forgotten. No new step and no new ordering hazard.
