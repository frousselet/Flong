# The digest

The main screen is not a list of articles. It is a list of **stories** : several articles, from several rooms, about one thing. That single change is what separates a tool for watching a subject from an aggregator, and everything else follows from it.

An aggregator shows what arrived, newest first, and leaves the reader to work out what matters. The digest shows what is happening, how many rooms are saying it, and whether it is still moving.

## What a story is

A group of at least two articles that share enough vocabulary. An article that shares enough with a story joins it ; one that shares enough with nothing waits, until another article shares enough with it.

Stories **grow**. An article arriving an hour later joins the story that is already there rather than opening a new one, which is what lets the screen say that something has been running for two hours and is still going. That is why they are stored rather than recomputed on each render, and why their identity is stable across runs.

A story stays open to new articles for three days. After that, an article about the same subject opens a new story, which is right : it is a new development, not the same one.

## Why vocabulary and not meaning

Section 11 proposed vectorizing a recent window of the stream for exactly this purpose. It was implemented, measured on a small French corpus, and abandoned.

| Pair | Similarity |
| ---- | ---------- |
| school calendar / **history of typography** | **0.931** |
| school calendar / school calendar, another paper | 0.919 |
| school calendar / Swift macros | 0.881 |

The system's sentence embeddings put two unrelated articles **above** two about the same event. A signal that cannot tell a school calendar from a history of typography is not a signal, whatever its numbers look like.

Shared vocabulary can. Reprints of one story share `académies`, `mi-août`, `calendrier` ; two unrelated articles share only the words everybody uses. Terms are weighted by how rare they are in the window being built, so a word used by one article in a hundred counts a hundred times more than one used by all of them, and the title counts twice, a headline saying what an article is about and a standfirst saying how.

It has a second virtue that was not the reason but might as well have been : it needs no model, so it works on every device, in the simulator, and in languages no embedding covers.

The vectors keep the job they are good at, which is finding a kept article by meaning in `docs/technical/background.md`. Their threshold there is now a distance from the crowd rather than a fixed value, for the same reason the table above gives.

## What is happening now

A story is live when **three articles from at least two rooms** arrived in the last six hours. Ten articles from one room is not an event ; it is one newsroom having a busy afternoon. The sparkline on each row shows the shape of the arrival, which is the one thing a number cannot say.

## Titles and summaries

The model names each story and writes its one-line summary, through guided generation : a model asked for prose returns prose, sometimes with a preamble in it ; asked for two fields, it returns two fields.

Without a model the story is named after its most central article and summarized by that article's own standfirst. The screen is entire either way ; it is only less well written. Section 14 requires anything a model wrote to say so, and the row carries a mark when it did, which the story page explains and offers to undo. How the page is set is in `docs/technical/interface.md`.

**The model writes in the reader's language, not the articles'.** Someone watching a subject follows whoever covers it, and a French reader on the English technical press wants a French headline over an English article : translating a headline is something the model does well, and it is most of the reason to have one here. The instructions name the language of `Locale.current` in English, which is what an English instruction is understood in. A locale the model does not support falls back to the articles' own language, since a model asked for a language it does not speak answers in a mixture of the two, which is worse than either.

Without a model the story takes the title of its most central article, so it is in that article's language. Translating without a translator is not something to fake.

**The language a brief was written in is stored with it.** Nothing else about a story changes when a reader changes the language of their device, so nothing else would ever ask for the brief to be written again, and the page would stay in a language its reader no longer reads. A brief whose language is not the reader's current one goes back in the queue, exactly as one written without a model does when a model turns up.

The rule for asking is one thing : **has the model been asked about this story, in this language?** A story it was never asked about is asked as soon as a model appears ; one it answered, refused, or answered in the wrong language has been asked, and asking again in the same language would get the same answer ; and a reader who changes language has changed the question. It is the language *asked in* rather than the language written in, because a refusal has no language, and counting a refusal as unanswered asked about it for ever.

**What comes back is checked against the language it was asked for**, by the system's own recognizer rather than by looking for words, and a brief in the wrong language is dropped for the article's own headline : better the language somebody chose to write in than a machine's wrong one. A headline too short to judge is taken at its word, since half the words in one are proper nouns that belong to no language at all.

**Where there is no model at all, the sources list says so**, and says which of the three reasons it is. A page whose stories are all named after their own articles and which carries no subjects is a page working exactly as section 14 says it should, and it looks exactly like a page that is broken. One line separates the two.

There is also a command, at the foot of the sources list, that throws away everything the model wrote and asks it again. Nothing normally needs it : it is there for the reader who wants a fresh reading of the page, and for the one whose model refused all morning and has since been switched back on, which is why it forgets the refusals on the way. A story whose headline the reader settled themselves is left alone by it, subject included.

The prompt is bounded before it is sent : six articles and two hundred and forty characters each, and where the system can count tokens exactly, a prompt that would leave no room for an answer is not sent at all. The cost of asking anyway is a refusal, and the cost of a refusal is a story with no headline.

## Subjects

A story is one event ; a subject is the field several events belong to. The difference is the whole reason the pills are worth having : filtering by `Éducation` says something the list of stories underneath does not already say, whereas a pill per story would be the same page twice.

## What the model is asked with

Everything the framework offers is used, and one thing it offers was measured and rejected. All of it is set in one place, `OnDeviceModel`, rather than at each call site.

**The permissive guardrails.** `SystemLanguageModel.Guardrails.permissiveContentTransformations` exists for an application that transforms content its reader already has, rather than one that generates content, and that is exactly this : a headline and one line about articles a publisher published and a reader subscribed to. The default set refuses a great deal of ordinary news, a court report, a war, a drug seizure, an epidemic, and every refusal arrives as a `guardrailViolation` and leaves a story wearing its own article's headline for no reason the reader can see.

**Greedy sampling, and a cap on the answer.** A headline is not a place for invention : the same story asked twice should come back the same, or a rebuild rewrites a page the reader was reading. Greedy is what makes it deterministic and it is free. The cap is generous rather than tight, since a structured answer cut off in the middle comes back as a `decodingFailure`, which reads as a refusal and is a worse outcome than a long answer.

**`prewarm`, in the one place it buys anything.** The summarizer measures its prompt against the context window before it asks, which is a real `await` ; the assets load during it. Everywhere else there is nothing to overlap with, and a prewarm invented a wait to have something to overlap with would cost what it saves.

**`supportsLocale`, and what it does not gate.** A language the model does not write is one it is not asked for : the instruction asks for the articles' own language instead, and the reader still gets a written headline over an article in the language they were going to read anyway. What the check gates is the test on the answer. Demanding the reader's language of an answer that was never asked in it rejected every brief and left the whole page wearing its articles' headlines, which is the one outcome both halves of this were written to avoid.

**`contentTagging` was measured and is not used.** Filing one headline under a list of labels looks like exactly what that tuned model is for. Against the three headlines the live tests have always used :

| Headline | `general` | `contentTagging` |
| -------- | --------- | ---------------- |
| `Une réforme du calendrier scolaire à l'étude` | `Éducation` | nothing |
| `Les macros Swift, deux ans après` | `Logiciel` | `Sport · Cybersécurité` |
| shown only `Jardinage` and `Cuisine` | nothing | `Cuisine · Jardinage` |

It extracts tags from a text rather than choosing among labels, so it answers with something whatever it is shown and never takes the way out. `Sport` is the same wrong answer the one-story-per-call design was written to stop. The live suite is what caught it, which is what that suite is for.

**Private Cloud Compute is not on the list, because there is no list to be on.** The framework gives third-party applications the on-device model and nothing else : there is no cloud, server or remote option anywhere in its interface. Apple's own features route to Private Cloud Compute ; an application's own prompts cannot. Section 3 would not have it anyway.

**A subject is a thing, not a reading.** The model used to name the subjects of the whole page on every rebuild, so they drifted : `Sécurité informatique` one run and `Cybersécurité` the next, and the preference the reader had attached to the first was left hanging off a name nothing used any more. There is a vocabulary now. It is written once, it stays, and a story is filed into it once and keeps it.

**Filing is a resumable job**, like the briefs and the vectors. **A story is asked about once, and answered about once**, which is not the same thing : the first version stamped a story as asked whatever had happened, so one guardrail refusal, one rate limit or one moment with the assets unloaded left a fil with no thématique for good, never asked again and with no way for the reader to give it one. That was the reader's report, and it was right.

The three answers are told apart now. The model choosing subjects, and the model choosing none, are both answers : the story is stamped, since asking again would get the same answer, and one the model cannot file would otherwise be asked at every opening and, since the unfiled are taken newest first, would sit at the head of the queue for ever and stop everything behind it from being asked at all. The model declining to write about this story is also an answer, and a durable one. But the model being unusable is not an answer about this story at all : nothing is stamped, the pass stops there, and the next one finds every story still waiting. `OnDeviceModel.isTheModelItself` already drew that line for the briefs ; the filing throws the information away no longer. The job counts what it asked rather than what it filed, so the queue empties instead of stalling on whatever it cannot answer. Nothing asks again : the command that did was replaced by a development one, and a story filed keeps what it was given. A fixed handful per run left a reader with a permanent backlog, since a page brings in more stories between two openings than a handful : it runs until the backlog is empty, the time runs out, or the model gives up, and picks up where it stopped at the next opening. A story is filed once and keeps it, so the backlog only ever shrinks.

**One story per call, and the answer chosen from a list.** The first version showed the model thirty numbered headlines and asked which numbers fell under which subjects. That is index bookkeeping, which a small model does badly : measured on a real page, it filed wildfires under `Sport` and a set of security advisories under `Économie · Sport · Politique · Sécurité`, every number in range and every one wrong. Asked about one headline at a time, against a schema whose subjects are the values of an enumeration it must choose from, it has nothing to keep track of and cannot answer something that is not a subject. Measured again on the same headlines : `Éducation`, `Logiciel`, `Typographie`, one each.

Two subjects at most. Given more it uses more, and the page that prompted this carried four on one story, of which one was right.

The list carries one way out, `None of these`, which is the only time the model is asked to name anything. What it names is checked before it is kept : one to three words, and nothing lifted out of the headline. Asked for a field and shown one headline, it answers with that headline about half the time, `Les macros Swift` where `Logiciel` was wanted, and a vocabulary of headlines is a vocabulary with one story in each. Told so, it answers `Technologie`. Twice wrong and the story is left unfiled, to be asked about again when the vocabulary has grown.

What comes back is folded against the vocabulary, case and accents ignored, so `cybersecurite` is filed under `Cybersécurité` rather than beside it.

**No date, ever.** The model is shown headlines and standfirsts and nothing else, so it has nothing to date anything by, and a model of this size fills that gap rather than leaving it : the reader saw briefs carrying years the articles never mentioned. The instructions forbid a date, a year or a day, and what comes back is checked for a four-digit year that appears in none of the articles it was shown. One the articles do carry is one it copied, and a story genuinely about a year may say so. One that appears nowhere was invented, and the brief is asked for again without it, exactly as a brief in the wrong language is. The page already says when a story arrived, to the minute, so the line above it loses nothing by not saying so too.

**Stories already filed are never re-read.** That is what makes the page stable. There is no second reading to ask for : the command that offered one is gone, and what remains of the mechanism is `discardWhatTheModelWrote`, which the language change still uses when a reader's language makes every brief wrong.

**The reader writes subjects too.** One they add is theirs, sits in the same vocabulary, and the model reaches for it as readily as its own. It is on the page from the moment it is written, before anything has been filed under it : a reader who writes a subject and cannot see it has no way of knowing it took. One the model found is on the page only while it holds something, since nobody asked for it. Narrowing to a subject that holds nothing says so, rather than saying nothing has come in, which would be untrue. It is also theirs to delete, along with everything filed under it ; a subject the model found is not, since deleting it would only have it found again on the next page, and what a reader wants from one of those is the preference. That is one call for the whole page rather than one per story, and it is a far easier question than naming the subject of a story in isolation, where there is nothing to compare it against. It runs after the briefs, since a written headline says what a story is about better than the title of whichever article happened to be nearest its middle.

What comes back is read with suspicion. A number that was never on the list is ignored, a story claimed twice keeps the first subject that claimed it, and a subject left holding nothing is dropped. Every story therefore ends up under exactly one subject or none, and a story under none is still on the front page : it is simply on no pill.

**A subject covering a single story is kept.** Dropping those was the first rule, on the argument that such a pill says what the story underneath already says. Measured against the real model it threw away everything : shown three stories, the model answers with three subjects covering one story each, so the rule left no subjects at all and the page looked exactly like a page with no model. That is what `TopicNamerLiveTests` exists to catch, since no test without a model can tell the two apart.

**The language is said twice, and the second time in the language itself.** Measured against the model, on English articles with a French reader :

| Where the demand is | What comes back |
| ------------------- | --------------- |
| in the instructions, in English | English |
| there and again after the articles | French, clumsy |
| there, and `not in English` after them | French, an English word left in |
| **there, and the demand written in French after them** | **French, and the best of the four** |

A model answers in the language of the words nearest its answer, and a sentence in that language is worth more than any number of sentences about it. So the demand is a translated string like any other, and a language the application is not translated into falls back to the English sentence about it rather than asking for the wrong language altogether. Said only once, at the top, A small model answers in the language of the words nearest its answer, and the headlines are nearer than the instructions ; three English headlines pulled the whole answer into English. The first version also gave `Education, Software, Typography` as examples of a subject, which primed it further. The examples are gone.

The whole set is rewritten on each rebuild. A subject is a reading of the page as it stands, and a page that has changed deserves a fresh one rather than yesterday's with today's stories bolted on. They are stored as a column on the story, never a table : a story is under one subject, subjects are derived data that is never synchronized, and a table would be three joins to say what a string says.

The front page looks back **three days**. Not a day, or a reader opening Flong on Monday morning would find a page emptied by the weekend ; not a month, since a front page is about what is current.

## When the model will not

A model that will not write about one story is not a model that has stopped working, and only the second is worth giving up on. `guardrailViolation`, `refusal`, `decodingFailure`, `exceededContextWindowSize` and `unsupportedGuide` are about the thing being asked ; `assetsUnavailable`, `unsupportedLanguageOrLocale`, `rateLimited` and `concurrentRequests` are about the model.

Only the second kind counts towards the three failures that leave the model alone for the rest of the run. Counting the first meant three awkward headlines in a row silenced it, and every story after them kept whatever it already said, in whatever language it already said it : a page of security advisories half in French and half in English.

## More of this, less of this

A long press on a subject moves it up or down, by one, between three and minus three. Nought is the absence of an opinion and is never stored, so the table holds one row per subject the reader has actually spoken about.

**The score comes before the weight, not mixed into it.** A reader who says more of this expects more of this, not a story two articles heavier than the one they asked for. What is happening now is ordered by when and by nothing else : asking for less of a subject is not asking to hear about it late.

**A story is under several subjects**, and takes the strongest thing said about any of them : asking for more of anything wins, and it is only when nothing about it was asked for that asking for less applies. An advisory about a stolen database is under both computer security and cybercrime, and a reader who asked for more of either meant this one.

The key is the name of the subject, because a subject has nothing else to be known by : it is written afresh by the model on each rebuild, and the reader pressed on a word rather than on a row of a table. A model that renames `Cybercriminalité` to `Cybersécurité` loses the preference attached to it, which is the price of a name being the only handle there is.

**It does not travel yet.** A preference is a choice, and choices are what this application synchronizes, so it ought to ; it would be one more record type, a few dozen records, well inside the budget of section 8. It is not done here, and a reader with two devices will state their preferences twice until it is.

## Pictures

A story shows the marks of the rooms covering it, in the order those rooms picked it up, which is the order a reader would tell it in. Four of them, and a count of the rest.

**A room is a host, not a feed.** A paper that publishes a feed per desk is one newsroom, not six : `leparisien.fr/societe/rss` and `leparisien.fr/politique/rss` are the same room, and a story both of them ran is one room covering it, not two. That is what decides whether anything is happening at all, since the live rule asks for several rooms and a paper running its own story in three sections is not several. The host is taken lowercased without its `www`, and not reduced to a registrable domain : that would need the public suffix list and would fold a paper and its unrelated blog into one.

A story shows the picture of its most recent illustrated article, since a story is shown for where it has got to rather than for where it started. The first story on the page runs it across the column ; the others keep it to a square at the side.

Where the picture itself comes from is in `docs/technical/ingestion.md`, and how it is fetched and drawn in `docs/technical/interface.md`.

## What is not a story

Articles that grouped with nothing are still there, under the tail, as the ordinary articles they are. A digest that hid them would be a digest that decides for the reader what they are allowed to have missed.

## Where it runs

Grouping is cheap and incremental, so it runs when the window opens and after every refresh. Naming is a call to a model per story, so it runs in batches of three, as a resumable job like the others in `docs/technical/background.md`.

Stories are derived data and are never synchronized. Another device holds the same articles and works out the same stories ; sending them would spend records to say what the other end already knows.
