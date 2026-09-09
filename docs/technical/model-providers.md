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

## Talking to a service

**The reader gives the base and the path is ours.** `https://api.openai.com/v1`, `http://192.168.1.20:11434/v1`, `https://openrouter.ai/api/v1` and a private gateway all work with the same code, and whatever `/v1` a service wants is part of what the reader typed. What is appended is `chat/completions` for the OpenAI format and `messages` for Anthropic's.

**Three rungs, and the one that answered is remembered.** A structured answer is a promise the OpenAI format makes and its imitators keep unevenly : some take a schema and hold the model to it, some take only `json_object` and want the shape said in words, and some four hundred on the parameter itself. There is no telling which without asking, so the question is put in the best way first, drops one rung on a refusal that names the parameter, and the rung that answered is written on the account so the next call starts where the last one ended. The cap on an answer is learnt the same way : OpenAI's reasoning models refuse `max_tokens` by name and want `max_completion_tokens`, and most of the services that copied the format have never heard of the second.

**The answer is checked against the shape again when it comes back.** A schema is a promise about the form of an answer and never about its values, which is why `TopicNamer` has always filtered what came back against the reader's own subjects. That filter covers the remote path unchanged.

**A conversation remembers, and remembers verbatim.** The turns are held here and sent again with every question, which is what makes `ask it again, it can see what it wrote` mean the same thing on both sides. What the model wrote is replayed word for word and never re-serialised : a re-serialisation with its keys in another order is not what it wrote, and asking it to correct a thing it did not say is asking it to correct somebody else.

**Four turns and no more.** Every turn carries every turn before it, so a loop that asked one more time would cost more each time it did. Four is what the writing actually uses : the brief, one complaint, the headline alone and the line alone.

**Anthropic's format has no ladder.** There is no `response_format` there and nothing to discover : the shape goes over as the input schema of one tool, the answer is required to be a call to it, and prose coming back instead is this story declining rather than the service failing. What the model wrote is replayed as its own words in a plain assistant turn rather than as the tool call it was : a `tool_use` in a transcript has to be answered by a `tool_result`, which would mean inventing a result for a tool that does nothing, and the tool is forced again on every turn anyway.

## What the transport does that a feed's does not

| | A feed | A model |
| - | ------ | ------- |
| Gap between bytes | 15 s | 120 s |
| Whole request | 60 s | 180 s |
| Body cap | 8 MB | 1 MB |
| Politeness | one a second per host, burst of four | none, and the pause on `Retry-After` kept |

**The fifteen seconds do not transpose.** A completion that does not stream sends nothing at all until the whole answer exists, so the gap between bytes *is* the generation ; for a feed it is a stall.

**The bucket is a different bucket.** The fetcher's is sized for politeness towards publishers and would serialize a night's filing behind a gate no publisher benefits from. What is kept is the half that matters : a service that answered `Retry-After` is left alone until then, or one refusal during a pass of two hundred stories becomes two hundred of them.

**A redirect that changes host is not followed**, and neither is one that steps down from `https` to `http`. `URLSession` strips `Authorization` across origins and leaves every other header alone : Anthropic's key travels in `x-api-key`, and a reader may add headers of their own, so a gateway answering a redirect to a host of its choosing would be handed the key by the system, silently, on the second request. A misconfiguration does it by accident and a hostile endpoint does it on purpose, and from here the two look the same.

**Plain HTTP goes to the reader's own network and nowhere else.** A model server they run has no TLS and never will : it is a process on their own machine, and it is the one configuration of this feature that sends nothing to anybody. `NSAllowsLocalNetworking` carries it to the private ranges, to link-local addresses and to `.local`, and every public host keeps App Transport Security in full. The editor makes the same check itself, so an address that would fail is refused with a sentence rather than with a number nobody can act on.

## Which models it offers, and the button that proves it

**The list is asked for and never assumed.** `GET /models` on both formats, once the key is in, filling a menu. A four hundred and four there is an answer rather than a failure : several servers a reader may point Flong at route only the completion path, and *the service will not say* is a perfectly good state. What is worth reporting from that call is a refused key, because it means the key itself is wrong and nothing further will work. The field beside the menu is always there, and typing a name is the ordinary path for a self-hosted endpoint rather than an apology.

**The two lists carry their moment differently.** OpenAI answers a number of seconds and Anthropic a date in words. Two readers, on purpose, so that nobody unifies them by mistake.

**The test is two calls and it proves four things.** The list first, which is free and separates an address nothing answers from a key that is refused ; then the real endpoint, the real model and the whole shape machinery, asking for the smallest structured answer there is. Sixteen tokens, and it proves the key, the address, the model name and which rung of the ladder this server actually stands on. The rung is written back on the account so the first real call does not repeat the first test's failure.

**It sends a fixed sentence and nothing of the reader's**, which is what makes it honest to offer before any consent has been given : somebody checking that their key works has not yet decided that their news may leave, and making them decide first would be asking them to agree to something they cannot yet check.

## The log

Section 14 asks for one clause : *outgoing calls are logged locally*. What the clause implies is a table with almost nothing in it.

| What a row holds | What no row holds |
| ---------------- | ----------------- |
| The moment, the duration | The prompt |
| Whose model, by name and by identifier | The articles |
| Which task, which host, which model | The answer |
| How it ended, and the status a server answered with | The key |
| What the service said it cost, where it said | The body of an error |

**The absence of the column is what enforces it**, and a test names the whole list so a column added later has to be added there too. A log that recorded the prompt would be a second copy of everything the consent was careful about, kept on the reader's own disk where nothing would ever purge it. A log that recorded an error body would be worse : several services echo the prompt there and one of them echoes the key.

**The provider is named twice on purpose.** The identifier points at an account the reader may delete tomorrow ; the name, the host and the model are copied onto the row. It is the rule an edition already follows against a story : a record of what happened must not change when the thing it happened to is edited or removed.

**One row per request and not per question.** A question that dropped a rung of the ladder cost two calls, and a log that hid the first would be one the reader could not reconcile with their bill.

**Two thousand rows and ninety days, whichever comes first**, trimmed once in a hundred inserts rather than on every one : a delete that scanned the table would run two hundred times during one filing pass for a bound nothing crosses in a night. It is not synchronized, and that costs no work : a table is only carried into CloudKit when the sync layer is told about it, and it will not be. What one device sent is a fact about that device.

## Who wrote it

Section 14 asks that anything produced automatically be flagged in the interface and in exports. With more than one model that stopped being a boolean.

**The mark stays one mark.** A glyph per provider would draw the application's own plumbing over the news, and there are as many of them as a reader configures. `StorySummary` already carries two, for two genuinely different claims : a line written here out of the articles below, and an editor's own line carried across into the reader's language. A third axis is one too many for a glyph inside a sentence.

**What is behind it names the author, because the sentence there was a promise.** It read *written on this device, from the articles below. Nothing was sent anywhere*, and for a headline written elsewhere the last clause is false. A story a provider wrote says who wrote it and does not make the promise, which is the one place in the application that sentence appears at all.

**The name is copied onto the story**, like the name of a provider on a call in the log : a record of who wrote something must not change when the account is renamed or deleted. Nothing on the column means this device, which is what it has always meant.

There is no export of stories to carry the field into yet ; the column is where it will come from when there is one.

## What is never in an error

**Nothing from the wire.** A service is free to put anything in the body of its own error and several put the prompt there ; one of them puts the key back. So the failures are a small closed set of five, the body is neither shown nor logged, and what a reader is told is one of five sentences written here. That is what makes `a key never reaches a message` a property a test can prove rather than a habit that decays.
