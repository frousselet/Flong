# Newsmakers

A feed says who **wrote** an article. Nothing in any feed format says who it is **about**. `docs/technical/authors.md` covers the first, which arrives as a field ; this page covers the second, which arrives as prose and has to be read out of it.

The difference is the whole reason this exists. A subscription follows a publisher, and a favourite author follows a byline. Neither can answer *what is being written about this person*, across every paper the reader follows, which is the question a reader of the news actually has.

## A newsmaker is a name, not a person

Exactly as an author is. What comes out of an article is a piece of text, and `E. Macron`, `Emmanuel Macron` and `le président français` are three of them that only a human eye can tell are one. **The name is the identity, matched exactly**, and Flong never guesses that two spellings are one person.

That is not a shortcut. The stored name is what a favourite is named after between devices (`newsmaker-<digest>`), so a rule that answered differently on two of them would give one person two rows and a favourite that only half travels. Everything below is deterministic for that reason.

## No model, and that is a requirement rather than a preference

`NLTagger` with the `.nameType` scheme, asked for `.personalName` and nothing else. Section 15 of the specification says the path without Apple Intelligence always exists and is always tested ; here there is no other path at all. The tagger ships with the system, runs on every device, and costs a few milliseconds per article.

Places and organizations are dropped. `SearchSubjects` wants all three, because a subject worth searching for is as often a country as a person ; this is a directory of people, and a country in it is a row nobody can follow.

The article's stated language is handed to the tagger. Ingestion settled it once and `LanguageDetection` already reduced `fr-FR` to `fr`, which is how `NLLanguage` spells it. It matters most for a headline : eight words are not much to detect a language from, and the tagger reads a headline it knows the language of far better.

## What is read, and how much of it

The headline, the standfirst and the plain text `EntryBody` already holds for the full-text index, joined with blank lines between them. They stand apart rather than running together : a headline has no full stop, and a standfirst joined straight onto it would give the tagger one sentence that is really two.

Forty thousand characters, which is a very long feature and several times the length of ordinary news. Past that a piece has said who it is about many times over, and the tagger costs time per character over a corpus of a hundred thousand.

Forty people per article. Almost nothing reaches it ; what it stops is the one article a year that is a list of two hundred names, which would otherwise be two hundred rows in a directory nobody can then read.

## What is cleaned off a span

`joinNames` is what makes `Donald Trump` one span rather than two words tagged in a row. It also joins too much, and it does it in ways a rule can see. Each of these is about spelling, each is mechanical, and none of them decides that two names are one person.

| Rule | Why it is safe |
| ---- | -------------- |
| Cut the span at every lower-case word that is not a particle | In a script that has capitals, every word of a name has one. `Eric Zemmour déborde Sarah Knafo` is two people with a verb between them, and `Céline Dion chante` is one person with a verb after her |
| Keep the particles | `de`, `du`, `van`, `von`, `der`, `bin` and the rest are a closed list a language changes about once a century, so `Dominique de Villepin` and `Mathieu van der Poel` come through whole |
| Drop a trailing particle | One left hanging is the start of a name the cut took away, not part of the one before it |
| Drop a leading acronym | `PDG Patrick Pouyanné`, `LFI Sébastien Delogu`, `NBA Patrick Beverley` : a job, a party, a league. A word in capitals is never a first name. Only where two words are left after it, which keeps `JR Smith` out of the rule |
| Refuse a word set entirely in capitals | `AI`, `CEO`, `COO`, `PIR`, `SREN` : a technology, two jobs, a party, a French statute, every one handed over as somebody's name |
| Refuse a span with a digit in it | A law or a squad number the tagger took for a person |
| Refuse more than five words | Past that the tagger has joined a run of names at the end of a sentence listing people |
| Refuse a span with no capital, where the script has them | A common noun the tagger mistook for a name. The test is for the **absence** of a capital, so a name in Chinese, Japanese or Arabic is kept rather than refused for lacking something its writing system does not have |
| Take off the article French elides on | `d'Emmanuel Macron`. What comes off has to be an article's length, so `aujourd'hui` keeps its own. The same rule `SearchSubjects` applies |

**Capitalization is left alone**, as it is for a byline : `Edouard Philippe` and `Édouard Philippe` are two spellings of one person, and deciding they are the same is a merge rather than a cleaning. The reader has the search field, which ignores accents and case.

**What is not cleaned is what no spelling rule can see.** `Cheval de Troie`, `James Webb Space Telescope` and `Here Comes Santa Claus` all reach the directory, because the tagger says they are people and nothing about how they are written says otherwise. That is the same limit `authors.md` records about `Rédaction` : deciding a well-formed name is not a person is a judgement about the world, not a fact about the spelling.

## Five articles, or the reader asked

601 people came out of a stream of 1,274 articles, and 498 of them were named by exactly one. A directory nobody can read is a directory nobody opens, so **the list is the people five distinct articles name**.

**The threshold is applied to the question, never to the reading.** Every name is stored. Somebody at four articles becomes somebody at five the moment the next one lands, and a rule applied on the way in could never let that happen. `NewsmakerStore.all()` filters, `collections()` counts the same set so the number under the square is the length of the list it opens, and `newsmaker(named:)` answers for anybody at all, since a favourite below the threshold still has a page.

**Articles and not mentions**, which the same measurement settled. Counting the times a name is written would have let through the portrait and the interview : `Ridley` named fourteen times in one article, `Anne Uginet` eleven, `Louis Mollard` eleven, each of them the subject of a single piece rather than somebody the press is covering. Two thirds of what that reading added was of that kind. What this page is for is the person several papers keep coming back to.

**What it costs is visible and was accepted.** Over a fortnight of sixteen feeds, five articles leaves 23 people and excludes Elon Musk at four, Mark Zuckerberg and Gérald Darmanin at three. A longer stream carries them over ; a purged one may take them back out, which is correct, since the directory says what this device holds.

**A decision the reader made is never hidden.** Somebody they singled out or asked to be told about is listed whatever their count, exactly as a favourite with nothing at all to their name is. The row is there so the decision can be seen and undone.

**The search field is the list's, and reaches no further.** Typing a name searches what the directory holds, so somebody at four articles is not found there either. That keeps the square's count, the list and the search saying one thing.

## A surname folds into the full name the same article gives it

A paper names somebody in full once and by their surname for the rest of the piece. Kept apart, `Donald Trump` and `Trump` are two rows, one holding the first paragraph of every article and the other holding the rest, and neither of them is the person.

So a name whose words are all inside a longer name **in the same article** is that person, and its mentions are theirs. `Trump` under `Donald Trump`, `Macron` under `Emmanuel Macron`.

**Only where there is one candidate.** An article about `Donald Trump` and `Melania Trump` says `Trump` too, and there is no telling which it meant. Two candidates fold nothing : the short name keeps a row of its own, which is the honest answer and the one the byline rules already give.

**Within the article and never across the store.** A rule that looked at what other articles had named would answer differently on two devices, and differently on the same device a week later. That is exactly what a name a favourite is stored under may not do. The cost is visible and accepted : an article that only ever writes `Trump` puts a `Trump` row in the directory beside `Donald Trump`.

## Whoever signed it is not somebody it is about

Plenty of publishers print the byline again at the foot of the prose. Left in, the writer would be in both directories at once, and the two would stop meaning different things. The byline goes through `Author.people(in:)` and the people it names are taken out of the reading.

## Where the reading happens, and why not at ingestion

`AuthorStore.index(_:byline:in:)` runs inside the ingestion transaction, because splitting a byline is a handful of string operations. This cannot : it is a model over a whole text, and run there it would hold the writer lock for the length of a model pass on every article of every refresh.

So v32 puts the answer on the article, and the work in two places :

- **What a pass has just brought is read in the pass**, before it announces anything. That is tens of articles and milliseconds, and it has to be there : `announceNewArticles` moves its watermark whether it said anything or not, so a person found a moment later would be a notice the reader never gets. This is also why `unread(limit:)` hands over the **newest** first.
- **The backlog is `NewsmakersJob`**, section 15's resumable work, run behind the page after the digest's own and again in the full pass. Nothing travels : each device reads its own stream under the same rules.

**`entry.newsmakers_at` is the resume point, and no rows is not the same answer.** An article that names nobody is a real answer, and one told apart from it only by having no rows would be read again at every pass, for ever. It is set back to `nil` when a publisher rewrites the title, the standfirst or the prose, which is what makes the people follow the text ; a refresh serves the twenty most recent articles of a feed every time, so this compares what is about to be written with what is stored rather than re-reading the lot.

A duplicate and a hidden article are not read : neither is shown anywhere, so a person named in one is a row leading nowhere. A duplicate whose original is later purged stops being one, its date is still `nil`, and it is read then.

## What the rows are asked

`entry_newsmaker` holds one row per person per article, with how many times the article named them. The mentions order the people of one piece : whoever it is about is named all the way through it, and the expert quoted in the eleventh paragraph is named once. That is what picks the name a notification is headed with when an article names two people the reader follows.

Every question about a person is asked of those rows. The directory is `GROUP BY name`, one person's page is `entry_id IN (SELECT ... WHERE name = ?)`, and the favourites square is the same with the name in `favourite_newsmaker`. The foreign key keeps it honest : an article that goes takes its people with it.

## What travels

Two record types, `FavouriteNewsmaker` and `NotifiedNewsmaker`, one record per name and the deletion is the `no`. The people themselves are never sent : they are worked out from the articles, and there is nothing to say about the thousands nobody has an opinion on.

**A prefix of its own, `newsmaker-` and `about-`.** The same name may perfectly well be a writer the reader follows and somebody they read about, and those are two different decisions. Sharing the writers' prefix would make one record of them, so singling out the writer would silently single out the subject.

## What it is measured against

A real stream of sixteen feeds and 1,274 shown articles yields around 600 people. The head of the list is what a reader would expect of the fortnight it covers, and the tail is the long run of people named once, which is what the search field and the favourites band exist for.

The rules above were each written against that measurement rather than in the abstract : the cut on a lower-case word removed `Eric Zemmour déborde Sarah Knafo` and `Grégory Allione rallie Édouard Philippe` and gave back four findable people ; the leading acronym removed five rows and gave `Sébastien Delogu` his six articles ; the capitals rule removed six rows, every one of which was noise and none of which was a person.
