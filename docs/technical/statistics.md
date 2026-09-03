# The figures

What the page of statistics counts, what it counts it from, and the four questions the schema cannot answer honestly. Section 16 of the specification says what the page is ; this says what is behind each number on it.

## The window

Eight, and `Tout` is the first of them and the one the page opens on : a reader opening a page of figures is asking what it all comes to, and a narrower window is a question they ask afterwards. It is also the page's best case, since a day on a device that has been collecting since the afternoon has almost nothing in it. Every figure and every chart on the page is about the one the reader picked. The window is measured back from now rather than snapped to a calendar : a reader opening the page at nine in the morning and asking for a day means the last twenty-four hours, not the ninety minutes since midnight.

**Everything is narrowed on `COALESCE(published_at, received_at)`**, which is the date the stream itself sorts by and the date `ArticleStore` already coalesces on everywhere else. A page of figures narrowed on `received_at` would count last week's arrivals as today's and disagree with the list it is figures about.

**Reading is the one exception**, and it has to be : when the reader read something is not when it was written, and a chart of their evenings drawn on publication dates would be a chart of somebody else's day. The reading series and the reading half of the day dial are narrowed on `read_at`.

Two clauses are on every count, exactly as they are on every list :

```sql
e.is_hidden = 0 AND e.duplicate_of IS NULL
```

A duplicate is never shown, so it must never be counted, or the page reports a fifth more articles than the reader was ever offered. On a real corpus that is twenty-one per cent of the rows.

## The grain

| Window | Grouped by | Marks |
| --- | --- | --- |
| a day | hour | 24 |
| a week, a month, three months | day | 7 to 91 |
| six and nine months | week | 26 to 40 |
| a year, everything | month | 12 upwards |

Between about twelve and forty marks whatever the window : fewer is a chart with nothing to say about its own shape, more is a row of hairlines.

**Weeks are grouped in Swift and not in SQLite.** SQLite counts a week from the first Sunday or the first Monday of the year depending on the letter used, and neither is necessarily the reader's own first weekday. Days are asked for and folded against `Calendar`, which is the only thing that knows where a reader's week begins.

**Every mark of the window is drawn, including the empty ones.** They are built by walking the calendar rather than by reading the rows back : a day nothing arrived on is a quiet day and has to keep its place, or a fortnight of silence draws as no gap at all.

**`Tout` begins where the stream starts running, not at its oldest article.** A feed serves its own archive, so a corpus collected last week routinely holds a piece dated 2017, and an axis stretched to reach it draws one bar and a hundred and twelve empty months. The walk begins at the earliest mark carrying a hundredth of the busiest. The straggler is still counted in every figure on the page ; it simply does not decide the shape of the chart.

## One snapshot

Every query runs inside one `database.writer.read`, so the figure at the head and the chart under it are counted from the same database rather than from whatever it happened to be between them. A refresh landing halfway through would otherwise leave a total that does not match its own parts.

The page is read when it opens and when the reader changes the window, and it is put down when they close it. It is a dozen counts over the whole stream : following the store the way the digest does would make every batch that lands cost a full recount of a page nobody may be looking at.

Everything crosses back out of the read block as plain values. A `Row` is not `Sendable`, and a block that hands one back picks GRDB's synchronous read, which would count a season of articles on the thread drawing the screen.

## The fourth figure

The grid opens on **Articles**, **Lus**, **Sources** and **Actualités** : how many arrived, how many were read, how many publishers spoke, and how many things the digest made of it, with `9 articles chacune` under the last.

It was a count of duplicates, which is a fact about Flong's plumbing rather than about the reader, and it was taken out for that. What replaced it says what the wire came to rather than how much of it there was : five thousand articles is a number nobody can hold, three hundred and nineteen things that happened is a season.

**The average is taken over the articles the stories gathered, not over the window.** The digest groups what it can, which on a real corpus is about fifty-seven per cent of what arrives ; dividing the whole window would count articles that are in no story towards the size of the ones that are.

## The glass

Every card and every figure tile on this page is a sheet of Liquid Glass, and the page stands on a wash : the theme's accent at the top of the screen and again at its foot, faint at both ends, with nothing in between.

**The wash is what makes the glass glass.** A material shows what is behind it, and a column of cards on one flat colour gives every card the same nothing to show : the glass is there and does not read as glass. The wash is fixed while the page scrolls over it, so the same card carries a different tint at the head of the page and at its foot, which is the whole of what the material is for.

The cards sit in one `GlassEffectContainer`, so the system merges neighbouring sheets and composites them once rather than stacking ten independent materials.

**The row of windows carries no ground of its own.** It is an inset in the safe area, which is what reserves its room ; painting the paper behind it would put the pills on a bar, and glass over an opaque colour is glass over nothing. What the cards go into as they pass under it is the scroll view's own soft edge.

This is a deliberate widening of the rule the rest of the application follows, where the material belongs to the navigation layer and to controls floating over a page. The author asked for it by name.

## The three dials

The hours of a day, the days of a week and the days of a month, each round a dial of however many places the unit has. One view draws all three : they differ in how many places they have, what is written round the edge and what the hole in the middle says, and three drawings would be three things to keep in step.

**A dial is only drawn where its unit comes round more than once in the window.** A dial is a comparison between the places on it, and a place that came round once is being compared with nothing : the days of the week over twenty-four hours is one spoke and six empty ones, and the days of the month over a week is seven of thirty-one. Both were drawn before `StatisticsRange.turns(every:)` existed, and both were nonsense. So the weekday dial wants a month and the day-of-month dial wants three ; the hours are on every window, a day of them being twenty-four places still worth comparing.

A dial and not a row of bars because every one of these units is round. A day wraps at midnight, a week at Sunday and a month at its last day ; a row of bars says the thing has a beginning and an end and that the two are as far apart as they look.

**SQLite counts a week from Sunday and a month from one.** `strftime('%w')` answers nought for Sunday whatever the reader's calendar says, and `strftime('%d')` answers one for the first. The store keeps the first convention and shifts the second so day one sits at index nought ; the weekday dial turns the array round to `Calendar.firstWeekday` when it draws it, which is the only thing that knows where a reader's week begins. A French reader's dial starts on Monday and an American one on Sunday.

**The last three places of the month dial stand for fewer days than the others.** A thirty-first comes round in seven months of twelve and a twenty-ninth in one year of four, so over a long window those spokes are quieter for a reason about the calendar rather than about the news. The count is what the card says it is ; dividing by the number of times the day came round would be an average of a count and no longer articles.

Two rules make the drawing readable at any distribution :

- **A spoke ends short of what is written round the edge.** At ninety-six hundredths of the radius the busiest one was drawn straight through the `L` of a Monday and the `1` of a first of the month.
- **A mark never gets wider than it is long.** Held at the full spoke width, one article against a busiest of twelve hundred was a lozenge lying across the ring : a seventh of the tallest spoke's height for a fourteen-hundredth of its value, and thirty-one of them round a month read as a dotted circle rather than as a quiet month.

## The publishers

Ranked by publisher and never by feed : `The Guardian` is followed here through three addresses, and a list naming all three would say the paper is a third of what it is.

`FeedURL.publisher(site:feed:)` cannot be expressed in SQLite, so the counts are grouped by `feed_id` and folded in Swift, which is what `AuthorStore` already does. A feed whose address says nothing usable is its own publisher, keyed by the feed itself so two of them never collapse into one.

**The name shown is the sources list's own**, looked up through `publishers[domain]`, so a publisher the reader renamed is called what they call it. The store carries a fallback for a publisher the list has no name for, and it is the title of whichever of its feeds gave the most : a name picked out of dictionary order would change between two readings of the same page.

## The subjects, counted in stories

A subject is filed onto a **story**, and reaches an article only through the story it was grouped into, so a story is its native grain.

Counting the articles underneath instead lets one runaway cluster carry a whole rubric. Measured on a real corpus : `Technologie` came to 1 256 articles off 40 stories, `Politique` to 252 off 41. Ranked by articles the first is five times the second ; ranked by stories they are the same size, and that is what the page actually looked like.

Only the articles the digest grouped carry a subject at all, which on that corpus is 45 % of them. The card says so in the line under its title rather than passing the ranking off as a reading of the whole stream.

## What is deliberately not on the page

**Words read, or time spent reading.** There is no word count in the schema and the only source for one is `entry_body.plain_text`, which is the publisher's feed body rather than the article. Measured on a real corpus, 3 252 of 5 956 bodies are under two hundred characters and one paper's median is **six**. A figure reading `vous avez lu 4 h 12` would be the length of teasers dressed up as articles. The honest half of the idea is the card above, which compares sources with each other instead.

**A daily reading curve as the whole truth.** `read_at` is written by `ArticleStore.setRead` and `markRead` and by nothing else. A read state merged from another of the reader's devices arrives through `ReadStateStore.apply` as a month and a fingerprint, and sets `is_read` with no moment to attach. So the *counts* of what was read are whole and the shape of *when* it was read is not. The page draws the reading only where at least three fifths of it carries a date, which is `Statistics.showsReading` ; below that the arrivals are drawn alone. Drawing a line along the floor of a chart is worse than drawing no line.

**A streak, or anything else that scores the reader.** Section 16 refuses the unread count as a debt nobody owes their feeds, and a run of consecutive days is the same idea with a nicer name. It would also be wrong for the reason above.

**What each feed puts in its body.** The median length of `entry_body.plain_text` per source, drawn as `Article complet` / `Extrait` / `Titre seul`. It was built and then taken out again, and both halves of why are worth keeping :

- **It makes an assertive claim about somebody else's publication from one number.** A publisher followed through several feeds has several medians and no way to add them, so the busiest feed was made to answer for the whole paper : Ars Technica's four feeds sit at 943, 1 063, 1 175 and 1 297, which straddles any threshold anybody picks. And a two-hundred-character chapô is a real summary, so calling Numerama and France Info `Titre seul` was simply wrong.
- **A corpus can hold bodies that are not bodies.** Measured on a real database, a feed named `Le Monde` had three hundred articles with a median body of six characters, because they were fixtures : titles `Article 0`, bodies `Corps.`, excerpts `Un chapô qui tient sur une ligne.` A card that ranks publishers by body length reports that as a fact about Le Monde.

**Sources that have gone quiet.** Measuring a feed against its own `observed_interval` is a good figure and it is not this page's : it is not a fact about a window, so it would be the one card on the page that ignores the control at the head of it. It belongs beside the feed health in the source editor.

## The words on it

Every label is a word the rest of the application already uses : `Sources`, `Auteurs`, `Personnalités`, `Thématiques`, `Langues`, `Doublons`, and a feed is a `flux` and never a `fil`.

The first cut of this page invented a synonym for each of them : `Qui publie` for the sources, `Signatures` for the authors, `Dans l'actualité` for the newsmakers, `Dit deux fois` for the duplicates, `Ce qui arrive dans le flux` for the body lengths. Every one of those is a phrase describing what the card does instead of naming what it holds, and the effect is a reader carrying two names for one thing. It is the same mistake the sources list already corrected when it stopped naming three desks of one paper separately.

The rule is in `CLAUDE.md` and it is worth repeating here because a page of figures is where it is easiest to break : say the thing that matters, then stop. `LocalizationTests.statisticsSpeakPlainly` is what notices if it drifts back.

## What has to fit

The page is measured at the accessibility type sizes as well as at the default one, because three things on it break there and each breaks silently :

- **The row of windows is a bar in the safe area and not a pinned header.** As a pinned header it kept its place in the scroll and drew no ground of its own, so the padding round the pills was space the cards were passing *through* rather than space between them : eight points, then thirteen, then twenty-two, and the card was against the pill every time, because what was under the pill was the card. An inset reserves the room, the page is laid out below it, and the soft scroll edge is what the cards go into as they pass. `Figures.gap` is the one rhythm every other block keeps : the figures were sixteen apart in their grid, fourteen across it and twenty-two from the cards, which reads as three relationships between things that have one.
- **A source's sparkline goes at an accessibility size.** It holds sixty points whatever the type does, and holding them cut `news.ycombinator.com` down to `news.yc…`, which is the one thing in the row nobody can do without. The count beside it is the row's fact ; the shape is a picture of it.
- **The dates under the flow chart go with it**, for the same reason : four of them across a phone at that size is two of them hanging off the ends. The line above the chart already names the mark and its count.

And one that breaks at the ordinary size too : **a date is centred under the mark it names**, so half of the first and half of the last hang off the ends of the plot. Running the chart the full width of its card painted `27 août` and `4 sept.` outside it, over the rounded corner and onto the page. The room is taken by padding the chart, `Figures.axisRoom`, and not through `chartPlotStyle` : insetting the plot leaves the labels centred on ticks at the frame's own edges, which is the same overflow one step further in.

The footnote under a figure is `Avant : 391` and not `+915 % par rapport à la période précédente`, which did not fit, made an absurd number out of a device that had been collecting for ten days, and asked the reader to undo a percentage to get at a fact.

## The foot of the page

There is an easter egg under the last card, a card's worth of quiet below it : `👉 🤓 👈`, and `Nerd` under that. It is past the end, so a reader who came for the numbers reads the numbers and never meets it, and a reader who kept scrolling after the numbers ran out is the reader it is for. Nothing about it can be pressed and it says nothing about the reader's stream.

It is one accessibility element carrying one word. Read out glyph by glyph it is two pointing hands and a face, which is a sentence nobody wants and not the joke.

## Cost

Every count is a `GROUP BY` in SQLite over indexed columns, and none of them returns more rows than the grain allows : a year is twelve rows however many articles fell in it. Measured on a corpus of 5 979 articles and 63 feeds, the whole page reads in well under a tenth of a second, the median body lengths included. The one query whose cost follows the corpus rather than the grain is the per-feed, per-mark flow, which is bounded by the number of feeds times the number of marks.
