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

There is also a command, at the foot of the sources list, that throws away everything the model wrote and asks it again. Nothing normally needs it : it is there for the reader who wants a fresh reading of the page, and for the one whose model refused all morning and has since been switched back on, which is why it forgets the refusals on the way. A story whose headline the reader settled themselves is left alone by it, subject included.

The prompt is bounded before it is sent : six articles and two hundred and forty characters each, and where the system can count tokens exactly, a prompt that would leave no room for an answer is not sent at all. The cost of asking anyway is a refusal, and the cost of a refusal is a story with no headline.

## Subjects

A story is one event ; a subject is the field several events belong to. The difference is the whole reason the pills are worth having : filtering by `Éducation` says something the list of stories underneath does not already say, whereas a pill per story would be the same page twice.

The model is given the headlines of the page, numbered, and answers with a handful of subjects and which numbers fall under each. That is one call for the whole page rather than one per story, and it is a far easier question than naming the subject of a story in isolation, where there is nothing to compare it against. It runs after the briefs, since a written headline says what a story is about better than the title of whichever article happened to be nearest its middle.

What comes back is read with suspicion. A number that was never on the list is ignored, a story claimed twice keeps the first subject that claimed it, and a subject covering fewer than two stories is dropped along with its claim. Every story therefore ends up under exactly one subject or none, and a story under none is still on the front page : it is simply on no pill.

The whole set is rewritten on each rebuild. A subject is a reading of the page as it stands, and a page that has changed deserves a fresh one rather than yesterday's with today's stories bolted on. They are stored as a column on the story, never a table : a story is under one subject, subjects are derived data that is never synchronized, and a table would be three joins to say what a string says.

The front page looks back **three days**. Not a day, or a reader opening Flong on Monday morning would find a page emptied by the weekend ; not a month, since a front page is about what is current.

## Pictures

A story shows the picture of its most recent illustrated article, since a story is shown for where it has got to rather than for where it started. The first story on the page runs it across the column ; the others keep it to a square at the side.

Where the picture itself comes from is in `docs/technical/ingestion.md`, and how it is fetched and drawn in `docs/technical/interface.md`.

## What is not a story

Articles that grouped with nothing are still there, under the tail, as the ordinary articles they are. A digest that hid them would be a digest that decides for the reader what they are allowed to have missed.

## Where it runs

Grouping is cheap and incremental, so it runs when the window opens and after every refresh. Naming is a call to a model per story, so it runs in batches of three, as a resumable job like the others in `docs/technical/background.md`.

Stories are derived data and are never synchronized. Another device holds the same articles and works out the same stories ; sending them would spend records to say what the other end already knows.
