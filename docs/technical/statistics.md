# The figures

What the page of statistics counts, what it counts it from, and the four questions the schema cannot answer honestly. Section 16 of the specification says what the page is ; this says what is behind each number on it.

## The window

Eight, from a day to everything, and every figure and every chart on the page is about the one the reader picked. The window is measured back from now rather than snapped to a calendar : a reader opening the page at nine in the morning and asking for a day means the last twenty-four hours, not the ninety minutes since midnight.

**Everything is narrowed on `COALESCE(published_at, received_at)`**, which is the date the stream itself sorts by and the date `ArticleStore` already coalesces on everywhere else. A page of figures narrowed on `received_at` would count last week's arrivals as today's and disagree with the list it is figures about.

**Reading is the one exception**, and it has to be : when the reader read something is not when it was written, and a chart of their evenings drawn on publication dates would be a chart of somebody else's day. The reading series and the reading half of the day dial are narrowed on `read_at`.

Two clauses are on every count, exactly as they are on every list :

```sql
e.is_hidden = 0 AND e.duplicate_of IS NULL
```

A duplicate is never shown, so it must never be counted, or the page reports a fifth more articles than the reader was ever offered. On a real corpus that is twenty-one per cent of the rows. **The one figure that inverts the second clause is the count of copies**, which is the whole point of it, and anybody tidying that query should leave it alone.

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

## The three dials

The hours of a day, the days of a week and the days of a month, each round a dial of however many places the unit has. One view draws all three : they differ in how many places they have, what is written round the edge and what the hole in the middle says, and three drawings would be three things to keep in step.

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

## What a source puts in its feed

The middle length of `entry_body.plain_text`, per feed, through a window function and never an average : one long read drags a mean across a whole publisher, and the question is what a typical article of theirs looks like.

A feed has to have published at least eight articles in the window to be measured. A median over two articles is one of those two, and a ranking by it would open on whoever published one long piece this week.

A median cannot be added to another median, so a publisher's three feeds cannot be folded the way their counts can. The busiest of them answers for the publisher, which is the one the reader mostly sees.

**The reader is shown a verdict and never the length.** Three bands, from `StatisticsStore.wholePiece` and `StatisticsStore.excerpt` :

| Median | Verdict |
| --- | --- |
| 1 200 characters and over | `Article complet` |
| 300 to 1 199 | `Extrait` |
| under 300 | `Titre seul` |

Two things were wrong with drawing the number instead. `3 461 caractères` is a true figure and a question rather than an answer : characters of what, and is that a lot. And the card cut the ranking in two and called the top half whole articles and the bottom half headlines, which is a verdict about a position rather than about a feed : a reader following eight generous sources had the bottom four of them accused of sending nothing. A length is measured against a length.

The bands are set against the corpus they were measured on : `theguardian.com` at 730 lands in the middle where it belongs, `bbc.co.uk` at 109 with the headlines, and `Le Monde` at six with them. `StatisticsTests.theVerdictIsAThreshold` pins the boundaries.

## What is deliberately not on the page

**Words read, or time spent reading.** There is no word count in the schema and the only source for one is `entry_body.plain_text`, which is the publisher's feed body rather than the article. Measured on a real corpus, 3 252 of 5 956 bodies are under two hundred characters and one paper's median is **six**. A figure reading `vous avez lu 4 h 12` would be the length of teasers dressed up as articles. The honest half of the idea is the card above, which compares sources with each other instead.

**A daily reading curve as the whole truth.** `read_at` is written by `ArticleStore.setRead` and `markRead` and by nothing else. A read state merged from another of the reader's devices arrives through `ReadStateStore.apply` as a month and a fingerprint, and sets `is_read` with no moment to attach. So the *counts* of what was read are whole and the shape of *when* it was read is not. The page draws the reading only where at least three fifths of it carries a date, which is `Statistics.showsReading` ; below that the arrivals are drawn alone. Drawing a line along the floor of a chart is worse than drawing no line.

**A streak, or anything else that scores the reader.** Section 16 refuses the unread count as a debt nobody owes their feeds, and a run of consecutive days is the same idea with a nicer name. It would also be wrong for the reason above.

**Sources that have gone quiet.** Measuring a feed against its own `observed_interval` is a good figure and it is not this page's : it is not a fact about a window, so it would be the one card on the page that ignores the control at the head of it. It belongs beside the feed health in the source editor.

## The words on it

Every label is a word the rest of the application already uses : `Sources`, `Auteurs`, `Personnalités`, `Thématiques`, `Langues`, `Doublons`, and a feed is a `flux` and never a `fil`.

The first cut of this page invented a synonym for each of them : `Qui publie` for the sources, `Signatures` for the authors, `Dans l'actualité` for the newsmakers, `Dit deux fois` for the duplicates, `Ce qui arrive dans le flux` for the body lengths. Every one of those is a phrase describing what the card does instead of naming what it holds, and the effect is a reader carrying two names for one thing. It is the same mistake the sources list already corrected when it stopped naming three desks of one paper separately.

The rule is in `CLAUDE.md` and it is worth repeating here because a page of figures is where it is easiest to break : say the thing that matters, then stop. `LocalizationTests.statisticsSpeakPlainly` is what notices if it drifts back.

## What has to fit

The page is measured at the accessibility type sizes as well as at the default one, because three things on it break there and each breaks silently :

- **The row of windows floats over the page**, so what separates it from the cards passing behind is the air it stands in and nothing else. `Figures.brim` is that air, and `Figures.gap` is the one rhythm every other block on the page keeps : the figures were sixteen apart in their grid, fourteen across it and twenty-two from the cards, which reads as three relationships between things that have one.
- **A source's sparkline goes at an accessibility size.** It holds sixty points whatever the type does, and holding them cut `news.ycombinator.com` down to `news.yc…`, which is the one thing in the row nobody can do without. The count beside it is the row's fact ; the shape is a picture of it.
- **The dates under the flow chart go with it**, for the same reason : four of them across a phone at that size is two of them hanging off the ends. The line above the chart already names the mark and its count.

And one that breaks at the ordinary size too : **a date is centred under the mark it names**, so half of the first and half of the last hang off the ends of the plot. Running the chart the full width of its card painted `27 août` and `4 sept.` outside it, over the rounded corner and onto the page. The room is taken by padding the chart, `Figures.axisRoom`, and not through `chartPlotStyle` : insetting the plot leaves the labels centred on ticks at the frame's own edges, which is the same overflow one step further in.

The footnote under a figure is `Avant : 391` and not `+915 % par rapport à la période précédente`, which did not fit, made an absurd number out of a device that had been collecting for ten days, and asked the reader to undo a percentage to get at a fact.

## Cost

Every count is a `GROUP BY` in SQLite over indexed columns, and none of them returns more rows than the grain allows : a year is twelve rows however many articles fell in it. Measured on a corpus of 5 979 articles and 63 feeds, the whole page reads in well under a tenth of a second, the median body lengths included. The one query whose cost follows the corpus rather than the grain is the per-feed, per-mark flow, which is bounded by the number of feeds times the number of marks.
