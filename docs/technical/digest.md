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

The prompt is bounded before it is sent : six articles and two hundred and forty characters each, and where the system can count tokens exactly, a prompt that would leave no room for an answer is not sent at all. The cost of asking anyway is a refusal, and the cost of a refusal is a story with no headline.

## What is not a story

Articles that grouped with nothing are still there, under the tail, as the ordinary articles they are. A digest that hid them would be a digest that decides for the reader what they are allowed to have missed.

## Where it runs

Grouping is cheap and incremental, so it runs when the window opens and after every refresh. Naming is a call to a model per story, so it runs in batches of three, as a resumable job like the others in `docs/technical/background.md`.

Stories are derived data and are never synchronized. Another device holds the same articles and works out the same stories ; sending them would spend records to say what the other end already knows.
