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

## What a headline has to be

A headline does two things at once : it says in a few words what the piece contains, and it makes somebody want to read it. The second is worthless without the first, which is why almost every rule below is about the first. What the model is told is the same thing a desk tells a new sub, put in the fewest words a small model can hold.

**Every word carries information.** The headline holds the most important words of the story and no others. `Le numérique en question` says nothing at all ; a fact, a figure, a named actor or a verb of action says something. Jargon is out.

**Short.** Up to about ten words sits comfortably in a reader's immediate memory ; past twelve it has stopped being a headline and become a sentence. Twelve is where the line is drawn rather than ten, so a good headline of eleven is not thrown away for being one over the ideal. The instruction alone does not hold it : asked for ten words a small model gives fifteen about as often as not, so the length is checked and a headline that overruns is asked for again.

**Clear before clever.** A plain headline barely trying to tempt anybody beats a pun nobody can parse. Wordplay, metaphor and reversal are legitimate craft and they need a readership and an editorial line to land ; a model writing for one reader it has never met has neither, so it is told not to try.

**Read out of context.** A headline here arrives in a list, with no page around it, and is often cut short, so the words a reader would look for go at the front.

**Never more than the articles say.** The gap between what a headline promises and what the piece delivers is what destroys the credit of a publication over time, and a reader's own front page is no different : one that oversells is one they stop believing. It is the single worst thing a generated headline can do, since nobody chose it and nobody is accountable for it.

**The headline and the line under it share the work.** They are one piece of furniture. The headline says what happened ; the standfirst states the angle, which is what this story is about of everything it could have been about, and answers what the headline had no room for : who, what, where and why. It prefers a fact, a figure or a named actor to a general statement, for the same reason the headline does.

**Of the five, *when* is deliberately missing.** A chapeau normally answers it. Here it must not : the model is shown no dates at all, only headlines and standfirsts, so it has nothing to date anything by and a model of this size fills the gap rather than leaving it. The page already says when a story arrived, to the minute, so nothing is lost by the line above it not saying so too. A year that appears in no source is caught and asked for again.

**A standfirst that restates the headline has spent the only line the story gets saying nothing new**, so that is checked, narrowly : the shape that actually comes back is the headline repeated with a clause bolted on, and a line that names the same subject and then goes on to say something is left alone. Rejecting the second would reject most of what the model writes correctly.

**One or two sentences, and past that it is the article**, which is one tap away. What is enforced is a ceiling in words rather than a count of sentences : a sentence tokenizer splits `M. Dupont` in two, and a standfirst rejected for naming somebody is a worse outcome than one that ran to three sentences. Forty-five words is generous on purpose, since what it is for is the model that writes a paragraph, and rejecting a good standfirst of forty-two costs the reader a real line for nothing.

**A standfirst that comes back wrong twice is asked for a third time, on its own.** The headline is settled and accepted by then, the session still holds everything that was written, and what is left to ask is one sentence : it is the cheapest question there is to put here, where asking for the brief again would put an approved headline back in play. The same move settles a headline that stayed too long. It happened to one story in fifty, which is often enough to land on the lead of the page, and a lead wearing a written headline over nothing is what a reader notices first.

**A line that is a paragraph three times over is cut rather than thrown away.** Whole sentences, in the model's own words and its own order, stopped at a full stop, and nothing at all where even the first sentence is a paragraph : a line stopped mid-thought under a headline is exactly what a truncated excerpt looks like. It is the last thing tried and never the first, since a model asked again for a shorter line writes a better one than any cut of the long one.

**The picture cannot be taken into account, and that settles the question rather than leaving it open.** A desk can let a headline lean on an explicit photograph and be the more tempting for it, and must load the headline with information when the photograph is metaphorical. Here the row's picture is whatever the publisher happened to attach and nothing has read it, so the headline carries the information every time.

**A story that resists a headline is usually a story that should not have been one.** On a desk, struggling to title a piece is a sign the piece has a problem. The same holds here : the grouping decides what a story is, and a group the model cannot name in ten words is often a group that put two events together.

The checks are one retry of the whole brief and no more, shared with the checks on dates and on language : whichever fault is found first is put to the model once, in the same session so it can see what it just wrote. What follows a second bad answer is not a third brief but a single field asked for on its own, which is a smaller question and gets a better answer.

## Two voices, and why there are two

**A third of a news reader's stories come back refused.** Measured over thirty real stories from a running page : ten of them, arriving as `refusal` or `guardrailViolation`, and the refusal carries `May contain sensitive content`. The stories it carries it for are floods, a war, an election, a lawsuit. That is the news, and a digest that drops a third of it is not a digest.

**The refusal is about what the model was shown, not about how it was asked.** Asked again, word for word, the same stories are refused again : sampling is greedy, so a refusal is as deterministic as an answer. Asking more politely changes nothing.

What does change something is describing the work accurately. A headline over six other headlines is not an opinion about a war ; it is six published sentences said in one. So a story the writing voice will not touch is put a second time as a transformation of published text, under instructions that say so and hold every other rule unchanged. Four of the ten came back, in the reader's own language rather than in the publisher's. Nothing is loosened to get them : the same guardrails, the same checks afterwards, and the same mark on the page saying the model wrote it.

A story both voices refuse is shown as its publisher wrote it, which is what the section below is about.

## Titles and summaries

The model names each story and writes its one-line summary, through guided generation : a model asked for prose returns prose, sometimes with a preamble in it ; asked for two fields, it returns two fields.

Without a model, or where both voices refuse, the story is shown as one of its own articles : that article's headline over that article's own standfirst. The screen is entire either way ; it is only less well written. Section 14 requires anything a model wrote to say so, and the row carries a mark when it did, which the story page explains and offers to undo. How the page is set is in `docs/technical/interface.md`.

**The model writes in the reader's language, not the articles'.** Someone watching a subject follows whoever covers it, and a French reader on the English technical press wants a French headline over an English article : translating a headline is something the model does well, and it is most of the reason to have one here. The instructions name the language of `Locale.current` in English, which is what an English instruction is understood in. A locale the model does not support falls back to the articles' own language, since a model asked for a language it does not speak answers in a mixture of the two, which is worse than either.

Without a model the story takes the title of its most central article, so it is in that article's language. Translating without a translator is not something to fake.

**The language a brief was written in is stored with it.** Nothing else about a story changes when a reader changes the language of their device, so nothing else would ever ask for the brief to be written again, and the page would stay in a language its reader no longer reads. A brief whose language is not the reader's current one goes back in the queue, exactly as one written without a model does when a model turns up.

The rule for asking is two things : **has the model been asked about these articles, in this language?**

**About these articles, and not about this story.** A story keeps one identity for life while its articles come and go : they join it as the press picks the subject up, and they leave it as a purge takes them or as they fall out of the three days the page reads. Nothing recorded which ones the model had been shown, so a story briefed on three articles about a protest kept that headline and that standfirst over the photography that had joined the group a week later, and a reader met a police headline above three pieces on lens choice. `story.brief_members` names the ones it was written from, sorted so the key is a set : the same articles in another order cost nothing, and a newcomer displacing the oldest of them is a new question.

**And they are the articles the reader is looking at.** The model used to be shown the most central members while the page showed the newest, which are two different lists : the headline could honestly describe articles nobody could see under it. It is shown the same six, newest first, for the reason the picture is taken from the newest member that carries one : a story is shown for where it has got to rather than for where it started.

**Whether there is a standfirst is not part of the question.** It was, and a brief may honestly have none : the model wrote a headline and its line came back a paragraph, or no article in the group carries a line a publisher wrote. Asked on the absence of a summary, every one of those came back at every pass for ever, and three of them in one batch stopped the whole phase.

The rest of the rule stands : A story it was never asked about is asked as soon as a model appears ; one it answered, refused, or answered in the wrong language has been asked, and asking again in the same language would get the same answer ; and a reader who changes language has changed the question. It is the language *asked in* rather than the language written in, because a refusal has no language, and counting a refusal as unanswered asked about it for ever.

**What comes back is checked against the language it was asked for**, by the system's own recognizer rather than by looking for words, and a brief in the wrong language is dropped for the article's own headline : better the language somebody chose to write in than a machine's wrong one. A headline too short to judge is taken at its word, since half the words in one are proper nouns that belong to no language at all.

**Where there is no model at all, the sources list says so**, and says which of the three reasons it is. A page whose stories are all named after their own articles and which carries no subjects is a page working exactly as section 14 says it should, and it looks exactly like a page that is broken. One line separates the two.

Nothing in the ordinary interface asks the model to re-read a page it has already read : stories already filed are never re-read, which is what makes the page stable. What used to need such a command is handled without asking, giving up on the model being a pause rather than a latch and the seeding of the sections asking again about the stories that were shown none.

`DigestService.discardWhatTheModelWrote()` survives as the primitive, sparing a headline the reader settled themselves, subject included. The one thing that calls it is the development repair of `docs/technical/sync.md`, which is meant to redo the whole of the work and would otherwise redo none of the model's half.

The prompt is bounded before it is sent : six articles and two hundred and forty characters each, and where the system can count tokens exactly, a prompt that would leave no room for an answer is not sent at all. The cost of asking anyway is a refusal, and the cost of a refusal is a story with no headline.

**The window is the device's own, and it says so itself.** `SystemLanguageModel.contextSize` is what the session holds, prompt and answer together. It is read at runtime rather than written down as four thousand and ninety-six : it is back deployed to the oldest system Flong runs on, where it answers exactly that, and on a newer one it answers whatever this device's model actually holds. The extra asks are measured against it too : a session carries its whole transcript into every answer, so the field asked for on its own is only asked for where what has already been said leaves room for it. Asked without room and refused for want of it, the story would be stamped as answered and keep nothing.

**A failure of the model is not an answer about the story.** A rate limit, an asset still downloading, a language this model does not write : none of them says anything about these articles, and stamping the story would leave it wearing its own headline for ever on a device that was busy for a second. A refusal is different : the model has read this and declined. The line was drawn in one of the three places a brief can fail and not in the other two, so a second call that hit a rate limit stamped what the first call would have left alone ; `StorySummarizer.outcome(of:)` is the one place it is drawn now, and it answers in the same three words the rest of the path speaks : the model wrote something, this story was declined under this voice, or the model itself is unusable.

**A standfirst the model did not write is never attributed to it.** A line that came back repeating the headline, or running to a paragraph, used to be replaced by the article's own excerpt while the brief stayed marked as generated : the page draws that mark on the standfirst and nowhere else, and VoiceOver read `Written by the model` over a sentence it had not written. It is asked for again on its own, and cut back to its first sentences where it is only too long ; where none of that works it is dropped. A headline the model wrote above no standfirst at all is the honest shape, and it is what is left after three tries rather than after two.

**And an excerpt is not a standfirst.** Where a publisher writes no summary, the excerpt is the top of the article body flattened and cut at three hundred characters on the nearest space : a sentence stopped in the middle with whatever the feed staples underneath. A release note went out as a standfirst, ticket numbers and a `Tags:` footer included. `StorySummarizer.standfirst(from:under:)` cuts the footers and drops what only repeats the headline or reads as a body.

**The headline and the line come from one article, or the line does not come.** The line used to be taken from whichever article in the group had one, under whichever headline came first. On a real page that put `Donald Trump's shallow renaming of the Great Lakes` over a line about a mapping application climbing the download charts, and `Farewell Keir Starmer` over a by-election in a London constituency : each half true, the pair about nothing. The whole head comes from the first article that has both now, and a group where no article carries a publisher's line is shown as a headline. Which headline moves with the line, and that is right : any member of a group stands for the group, and one that arrives with its own line stands for it better.

**The reader's own language decides between the members.** A group about one event is regularly covered in two languages, and where one of its articles is already in the language the reader reads in, that is the article the page shows. It is the whole of what can honestly be done for the language of a story nobody wrote a brief for : the alternative is machine-translating somebody else's headline and printing it as theirs, and the translations measured here dropped the sense of one headline in four.

**The furniture a template staples to a headline comes off.** `| Letters`, `| First Thing`, `| Polly Toynbee` : the section, the newsletter or the columnist, added after the headline by whichever system built the feed. It says where the piece ran and never what happened. Only what follows the last pipe, only where that is short, and only where what stands before it is still a headline.

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

## Two natures of subject

| Nature | Who decided | May the reader delete it |
| ------ | ----------- | ------------------------ |
| **standard** | a century of newspapers | no, it was not made |
| **own** | the reader | yes |

Both are shown to the model, the reader's own first. There was a third, **smart**, coined by the model when nothing it was shown fitted, and it is gone.

**The model no longer names anything.** What came of letting it was a drift of near synonyms of the sections that already existed : `Science` beside `Sciences`, `Sports` beside `Sport`, each one the English word for a section the reader already had, wearing the model's own mark and taking a pill of its own. The language was demanded twice, in the instructions and again after the headline, and it was not enough, for the reason recorded elsewhere on this page : a model answers in the language of the words nearest its answer, and the words nearest that answer were an English headline from the English press.

Showing it the reader's own vocabulary fixed the language and would not have fixed the shape of the thing. A subject a reader cannot delete, cannot rename and did not ask for, invented one story at a time, is a vocabulary that grows in a direction nobody chose.

**So the catalogue was widened instead, from thirteen to fifty.** Thirteen was a set of desks and everything finer landed on the nearest one, which is what the second pass was really reaching for. A gap in a list nothing may go outside of is a story misfiled for ever, so the list has to be deep enough that most stories meet something exact : `Intelligence artificielle`, `Cybersécurité`, `Vie privée`, `Réseaux sociaux`, `Jeux vidéo`, `Séries`, `Faits divers`, `Consommation`, `Météo` are sections a reader follows, not desks a newsroom has.

Fifty is also few enough that a reader can hold an opinion about each name, which is the other half of what a vocabulary is for.

**`Société` and `Culture` are last on purpose.** They are the two that sort nothing, and they are kept because they are the fallbacks and because existing stores carry them. The model reads the list in order and is told to prefer the most exact subject that fits, so it should meet them after everything that says something.

**The names are English in the code and French in the catalogue.** The string catalogue's source language is English, so an English key with a French translation is the way round it is meant to be. It was the other way about, which made every section a French word hard-coded in Swift.

They are stored in the reader's language, and seeded at launch rather than in a migration : a migration runs before anything has asked what that language is. The cost is that a reader who changes language keeps the names they had.

**A section that is renamed takes its stories and the reader's opinion with it.** A section is known by its name and by nothing else : `topic.name`, `story_topic.name` and `topic_preference.name` are all the resolved string, so renaming one without moving the other two leaves the stories filed under a name that no longer exists and the reader's word attached to it. A rename that would land on a section that already exists is left alone, since merging two sections is a different decision and not one a rename may take by itself.

`Écologie` is the one that forced this. In French it names the political movement first, so a story about the party filed under it rather than under `Politique` ; and in English the same key was translated `Climate`, which would have folded a whole ecology backlog into the narrower `Climat` the catalogue now adds beside it.

**What the model had already named is dealt with by a migration.** A subject the reader had spoken about becomes theirs, since they pressed it up or down and a preference nobody can find is a preference nobody can undo. Everything else goes, and its filings with it : `story_topic` has no key on `topic`, so a filing left behind would be a pill the reader can see on the front page and cannot find, cannot manage and cannot remove. A story left under nothing has its stamp lifted, since it was answered by a vocabulary that no longer exists.

The cost is stated plainly : rubrics lose their finer half, and `Politique · Réforme des retraites` becomes `Politique` until the catalogue happens to hold the finer name. That is the trade, and the fifty are what make it worth taking.

**Filing is one pass, and it has no way out.** The list is the whole vocabulary, and a headline belonging under none of fifty sections is rare enough that an escape costs more than it saves : measured before this, the model took the escape constantly, and a page where half the stories are filed under nothing is a page whose pills say nothing. It cannot invent either, the schema being an enumeration of the names it was given.

Two subjects at most. Given more it uses more, and the page that prompted that limit carried four on one story, of which one was right.

**A subject is held to the rules a headline is held to**, and now they govern the catalogue rather than what the model may coin. They are the same job at different lengths : a headline says what one story is, a subject says what a run of them is about, and both fail the same way, by using words that carry no information. One or two words, each of them working ; the most exact that fits rather than the broadest that would do, since filing a school-calendar reform under `Politique` when `Éducation` is on the list is filing it where nobody will look for it.

**A subject is a thing, not a reading.** The model used to name the subjects of the whole page on every rebuild, so they drifted : `Sécurité informatique` one run and `Cybersécurité` the next, and the preference the reader had attached to the first was left hanging off a name nothing used any more. There is a vocabulary now. It is written once, it stays, and a story is filed into it once and keeps it.

**Filing is a resumable job**, like the briefs and the vectors. **A story is asked about once, and answered about once**, which is not the same thing : the first version stamped a story as asked whatever had happened, so one guardrail refusal, one rate limit or one moment with the assets unloaded left a fil with no thématique for good, never asked again and with no way for the reader to give it one. That was the reader's report, and it was right.

**A vocabulary with nothing in it is a third thing, and was read as one of the two.** `TopicNamer.file` gave back `chosen([])` when it was shown no subjects, which reads as the model having considered the story and placed it under nothing : the caller stamped it as asked and never came back. Nothing had been asked at all. The migration that gave subjects their natures marked every existing one as the model's own, so the settled list was empty for one run and a whole page of stories was stamped as answered by a question nobody ever put. It is a model that cannot be used now, so nothing is stamped and the queue keeps its place ; and the vocabulary is read once per batch and allowed to throw rather than being read per story with its failure swallowed.

**And the stamp is lifted when the vocabulary catches up.** A story is asked once because asking again would get the same answer, which stops being true when the answer was decided by a vocabulary that has since changed. Seeding the sections asks again about every story filed under none of them, so a reader already using Flong gets the sections applied to the page they have rather than to the page they will have. A story already under something settled keeps its answer.

The three answers are told apart now. The model choosing subjects, and the model choosing none, are both answers : the story is stamped, since asking again would get the same answer, and one the model cannot file would otherwise be asked at every opening and, since the unfiled are taken newest first, would sit at the head of the queue for ever and stop everything behind it from being asked at all. The model declining to write about this story is also an answer, and a durable one. But the model being unusable is not an answer about this story at all : nothing is stamped, the pass stops there, and the next one finds every story still waiting. `OnDeviceModel.isTheModelItself` already drew that line for the briefs ; the filing throws the information away no longer. The job counts what it asked rather than what it filed, so the queue empties instead of stalling on whatever it cannot answer. Nothing asks again : the command that did was replaced by a development one, and a story filed keeps what it was given. A fixed handful per run left a reader with a permanent backlog, since a page brings in more stories between two openings than a handful : it runs until the backlog is empty, the time runs out, or the model gives up, and picks up where it stopped at the next opening. A story is filed once and keeps it, so the backlog only ever shrinks.

**One story per call, and the answer chosen from a list.** The first version showed the model thirty numbered headlines and asked which numbers fell under which subjects. That is index bookkeeping, which a small model does badly : measured on a real page, it filed wildfires under `Sport` and a set of security advisories under `Économie · Sport · Politique · Sécurité`, every number in range and every one wrong. Asked about one headline at a time, against a schema whose subjects are the values of an enumeration it must choose from, it has nothing to keep track of and cannot answer something that is not a subject. Measured again on the same headlines : `Éducation`, `Logiciel`, `Typographie`, one each.

Two subjects at most. Given more it uses more, and the page that prompted this carried four on one story, of which one was right.

The list carries no way out. It did, and the model took it constantly ; then it named a subject of its own at the end of it, which is the pass that has since been removed altogether. Fifty sections are what stand in for both.

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

## What the filing was asked about

The same rule as the brief, for the same reason. A story the model declined, or answered about with nothing, was stamped as asked and never asked again : one refusal on one border report and it stood under no rubric for the rest of its life, invisible to every pill, with no gesture anywhere that could give it one. And the filing outruns the writing - a brief costs three model calls to a filing's one - so a story could be filed on the raw headline of whichever article was nearest the middle of the group, and then keep that rubric under the headline the model wrote afterwards.

`story.topics_asked_for` holds the headline and the head of the standfirst, which is the whole of what the model is asked. A story whose question has changed is asked again. And the queue takes the briefed first, so the durable answer is decided on the written headline rather than on the raw one : deferred, never blocked, since a story that never gets a standfirst is still filed, behind the ones that have one.

## When the model will not

A model that will not write about one story is not a model that has stopped working, and only the second is worth giving up on. `guardrailViolation`, `refusal`, `decodingFailure`, `exceededContextWindowSize` and `unsupportedGuide` are about the thing being asked ; `assetsUnavailable`, `unsupportedLanguageOrLocale`, `rateLimited` and `concurrentRequests` are about the model.

Only the second kind counts towards the three failures that leave the model alone for the rest of the run. Counting the first meant three awkward headlines in a row silenced it, and every story after them kept whatever it already said, in whatever language it already said it : a page of security advisories half in French and half in English.

## More of this, less of this

A long press on a subject moves it up or down, by one, between three and minus three. Nought is the absence of an opinion and is never stored, so the table holds one row per subject the reader has actually spoken about.

**The score comes before the weight, not mixed into it.** A reader who says more of this expects more of this, not a story two articles heavier than the one they asked for. What is happening now is ordered by when and by nothing else : asking for less of a subject is not asking to hear about it late.

**Then when, and only then how heavy.** Weight came second, and a reader who has said nothing about anything, which is every reader for their first days, had a page ordered by article count alone. A story that has run all week keeps gathering articles and outweighs anything that opened this morning, and outweighs it more every day : the top of the page was the same top of the page every morning however much had arrived overnight, which is a front page saying nothing has happened. A newspaper orders the day's news by the day.

**A story is under several subjects**, and takes the strongest thing said about any of them : asking for more of anything wins, and it is only when nothing about it was asked for that asking for less applies. An advisory about a stolen database is under both computer security and cybercrime, and a reader who asked for more of either meant this one.

The key is the name of the subject, because a subject has nothing else to be known by : it is written afresh by the model on each rebuild, and the reader pressed on a word rather than on a row of a table. A model that renames `Cybercriminalité` to `Cybersécurité` loses the preference attached to it, which is the price of a name being the only handle there is.

**It does not travel yet.** A preference is a choice, and choices are what this application synchronizes, so it ought to ; it would be one more record type, a few dozen records, well inside the budget of section 8. It is not done here, and a reader with two devices will state their preferences twice until it is.

## Pictures

A story shows the marks of the rooms covering it, in the order those rooms picked it up, which is the order a reader would tell it in. Four of them, and a count of the rest.

**A room is a host, not a feed.** A paper that publishes a feed per desk is one newsroom, not six : `leparisien.fr/societe/rss` and `leparisien.fr/politique/rss` are the same room, and a story both of them ran is one room covering it, not two. That is what decides whether anything is happening at all, since the live rule asks for several rooms and a paper running its own story in three sections is not several. The host is taken lowercased without its `www`, and not reduced to a registrable domain : that would need the public suffix list and would fold a paper and its unrelated blog into one.

A story shows the picture of its most recent illustrated article, since a story is shown for where it has got to rather than for where it started. The first story on the page runs it across the column ; the others keep it to a square at the side.

Where the picture itself comes from is in `docs/technical/ingestion.md`, and how it is fetched and drawn in `docs/technical/interface.md`.

## What is not a story

Articles that grouped with nothing are still there, in the wire, as the ordinary articles they are. A digest that hid them would be a digest that decides for the reader what they are allowed to have missed.

**They were under a tail on the front page, and the tail is gone.** The argument above is why it existed and it is still the argument ; what changed is that the wire answers it. The section beside the digest shows everything, newest first, read or not, so the bottom of the front page was a shorter copy of the page next door, and a reader who scrolled past the stories arrived at the same list they would have found by moving one tab across. A front page carries what is happening. What merely arrived has a section of its own, and nothing is decided for anybody by saying so.

The count went with it. `Digest.isEmpty` asked whether there were stories *or* loose articles, which was right while the tail was drawn and would now leave a page rendering blank while insisting it is not empty.

## Where it runs

Grouping is cheap and incremental, so it runs after every refresh, which now means every one : the clock, the return to the foreground, the background refresh and the full pass all go through the one entry point that fetches, groups and reads the page back. It said this before and only three of those honoured it, which is why a window left open gained articles and no stories.

Naming is a call to a model per story, so it runs in batches of three, as a resumable job like the others in `docs/technical/background.md`.

**The headlines and the subjects take turns, and both are bounded.** They ran one after the other with no deadline at all, so a night that brought sixty stories spent every call the model would take on headlines and the subjects were never asked for : the reader woke to a page fully written and filed under nothing. Each gets a slice, in turn, until there is nothing left to do or no time left to do it in. The briefs still go first within a turn, a written headline being a better thing to file than the title of whichever article was nearest the middle of the group.

Stories are derived data and are never synchronized. Another device holds the same articles and works out the same stories ; sending them would spend records to say what the other end already knows.
