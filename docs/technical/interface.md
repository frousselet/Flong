# The interface

Flong is meant to be a tool for watching a subject, not another aggregator. An aggregator is a list of what arrived ; a tool for watching says what is happening, who is saying it, and whether it is still moving. The interface exists to make that difference visible, and every decision below follows from it.

## One column

The three-pane layout is what every reader ships, and it is a poor fit for reading. Two columns of chrome around an article are two columns of not reading, and on iPhone the third pane never existed anyway. Flong shows one thing at a time : the digest, then a story, then an article, each pushed onto a stack, each with its own way back.

Sections keep their own stack, so leaving the collections in the middle of something and coming back lands where the reader was, not at the beginning of everything.

## Set like a page, not like a control panel

Boxes are what an interface reaches for when it does not trust its own typography. A card has a border, a fill, a shadow and a corner radius, and all four exist to say *this is a thing* : type already says that, with a rule and some air.

So the digest is set as an editor would set a page :

| Token | Value | Why |
| ----- | ----- | --- |
| `measure` | 680 pt | The column stops there whatever the window does. A line of text past about 80 characters is a line the eye loses. |
| `rhythm` / `tightRhythm` | 28 / 10 pt | Two spacings, used everywhere, so the page has a pulse rather than forty arbitrary gaps. |
| `headline` | system serif, semibold | Serif for what was written, sans for what the application says about it. The two voices stay apart without a single line of chrome. |
| `metadata` | caption, tertiary | The facts under a story are for the reader who asks, not for the one who scans. |

They live in `Flong/Support/Editorial.swift`. A screen that needs a fifth spacing value is a screen that has gone wrong.

Section headers are uppercase, kerned, secondary, and a hairline rule sits above each row. That is the whole vocabulary. No card, no box, no shadow, no glass in the content.

## Liquid Glass belongs to the navigation layer

Apple's guidance for the 2026 material is explicit : glass is the layer that floats **over** the content, and glass must never sit on glass. Both halves matter, and the second one is easy to break by accident.

Flong broke it once. A hand-rolled floating bar in `safeAreaBar(edge: .bottom)`, drawn with `glassEffect`, collided on iPhone with the system search field, which is also glass : two blurred capsules overlapping, each refracting the other. The fix was not to tune the material but to delete the bar. The sections are a system `TabView`, the search tab carries `role: .search` so the system puts search where the system puts search, and `tabBarMinimizeBehavior(.onScrollDown)` gets the bar out of the way when the reader scrolls into something.

The application draws glass in exactly one place of its own : the subject pills at the top of the digest. That is the same rule, not an exception to it. A pill is a control floating over the page, which is the layer the material is for, and the row sits in the content and scrolls away with it rather than pinning itself under the tab bar, where it would be glass directly under glass.

Everywhere else the glass on screen is the system's.

On macOS the same four sections become a sidebar, through `tabViewStyle(.sidebarAdaptable)` : there is no bar to minimize on a Mac, and a window is already out of its own way.

## Pictures

An editorial page without pictures is a page of grey, and a page where every picture is the same size is a list. So there is a hierarchy of exactly one : **the first story runs its picture across the column**, in a band rather than a square, above a larger headline ; everything below it keeps its picture to a square at the side. That is how a front page has said what matters for two centuries, and it costs one line of code to say it.

Every picture is shown at three by two, lead and thumbnail alike. That is what a camera takes and therefore what a publisher's picture already is : any other ratio is a crop, and a crop is a decision about somebody else's photograph. One ratio for the whole page rather than a band above and squares beside, since a column whose pictures are all the same shape has a rhythm and one whose pictures each have their own does not.

It is `Editorial.pictureAspect`, named once. Across a column of six hundred and eighty points a lead runs to four hundred and fifty, which is most of an iPad screen : the trade is fewer stories at a glance in exchange for pictures nobody has cropped.

Beside a picture on a phone the facts line runs out of room, and a line that wraps to hyphenate `rédac-tions` is worse than a line that says less. `ViewThatFits` drops the sparkline first, then the article count : what survives is who is talking and when they last did, which is the irreducible part.

`AsyncImage` is not used. It keeps no decoded image, so scrolling back up decodes everything again, and it decodes at full size, so a two thousand pixel photograph is unpacked whole to fill a sixty four point square. `ImageStore` makes the thumbnail straight from the encoded bytes with `ImageIO`, which is faster and an order of magnitude cheaper in memory, and keeps the result at the size it was asked for.

A picture occupies nothing until it has something to show, and nothing again if the address turns out to be dead : a grey rectangle where a photograph failed is worse than no photograph, and a page of them looks broken. It is decorative and hidden from VoiceOver, since feeds almost never carry alternative text and reading a headline out twice helps nobody.

## The mark of a source

A list of feeds is a list of names, and names take reading. A mark is recognized before it is read, which is the whole of what a favicon is for. It stands beside a feed in the sources list, in place of the generic symbol, and beside the name of the room on every article row.

On the digest it stands **in place of the count of rooms**. `4 rédactions` is a number the reader has to turn back into rooms ; four marks are the rooms, and they say which ones, which is the question behind the number : a story every paper is running and a story only the trade press is running are not the same story. Four are shown, and a fifth room becomes a `+1`. The count survives for anyone listening to the page rather than looking at it, since the row of marks carries it as its accessibility label.

Three addresses are tried, in order : **what the feed states**, since the publisher chose it ; **`apple-touch-icon.png`**, a well-known path, square by convention and large enough to stay crisp where a sixteen pixel favicon would not ; and **`favicon.ico`**, the oldest well-known path and still the most widely served, since browsers ask for it whether a page mentions it or not. The well-known ones hang off the root of the site, never off the page the feed happens to point at.

Nothing is asked for until a row is on screen, and what comes back is kept on disk, so a feed costs one request rather than one per appearance. A feed that answers none of the three wears the generic mark : a list of sources must keep its column of marks whether a publisher serves one or not, which is the one place a picture does not simply vanish when it fails.

## Motion that says something

Motion is either information or decoration, and decoration on a screen read every morning becomes noise by the second week. Three movements survive :

- **A story page grows out of the row that opened it**, through `navigationTransition(.zoom(sourceID:in:))` and `matchedTransitionSource`. The motion says where the page came from, which is the one thing a push animation cannot. iOS and iPadOS only : macOS has no such transition and needs none.
- **The rule under the period slides** from `Day` to `Week` rather than blinking on, through `matchedGeometryEffect`. It is the same object moving, so it moves.
- **The live dot breathes**, and stops breathing under Reduce Motion, where it becomes a plain dot that still reads as red.

Nothing else animates.

## The stream

The section beside the digest shows everything, newest first, read or not. A queue is a thing to get to the end of, and a reader watching a subject is not trying to finish anything : what they want is to see what came in, and where they left off.

**A read article is marked, not diminished.** It carried a blue dot when unread and a lighter headline when read, which made half the page look stale and quietly said that a story already opened was worth less. Every headline keeps one weight and one colour now, and a read one ends in a small tick : at the end of the words rather than beside them, where the reader stopped reading, costing the row no width. The section carries no count either. A number that only ever grows is a debt, and nobody owes their feeds anything ; the sources list still counts what is unread, for whoever wants to know.

It is broken by day, in the same kerned uppercase as the front page's sections. A long scroll with no landmarks is one a reader loses their place in, and the day is the landmark.

Unread on its own is still a view, in the sources list, for whoever wants a queue.

**It is called `Flux` in French, and the subscriptions are no longer.** `Flux` is what a French reader calls the river of everything, and it was already the heading over the list of feeds in the sources screen. Two sections cannot share a name, and the list of feeds is a list of subscriptions, which is what it is now called. In English the section is `Stream`, the specification's own word for the disposable cache of everything, which is exactly what it shows.

Its title is a large one, like the front page's dateline and the sources list, so it stands at the head of the page and shrinks into the bar as the reader scrolls into it. An inline title is already shrunk : it says where you are without ever saying it was worth a line.

## The month over the stream

A row of bars is pinned at the head of the stream, one per day, a month at a time. It answers the question a reader has when they open a wire after two days away and cannot answer from a list : was this month steady, or did it have a Thursday in it.

**Exactly the days the month has.** A rolling stretch of thirty is a stretch nobody keeps and cannot be compared with the one beside it ; a month can. February draws twenty-eight bars and August thirty-one, each a little wider or narrower for it, which is a fact about February rather than a gap in the drawing. It is counted through `Calendar` rather than by adding days, which is also what makes it right in a calendar that is not Gregorian, where a month is not thirty-odd days at all.

**No axis and no legend.** Thirty numbers down the side and thirty dates along the bottom would take more room than the chart and say less than its shape does, and the dateline of whatever is on screen is one line below anyway.

**The rest of the month is drawn, and greyed.** A day that has not happened yet is not a quiet day, and stopping at today would have the current month change width as it goes. The days ahead keep their places at the height of a day with nothing in it and say in grey that there is nothing there to have. This is the one place a bar is drawn for a day with no articles : a day gone by that nothing came in on draws nothing at all, since with no axis to stand on there is no line for it to hide in, and a gap in the row is the honest picture of a gap in the month.

**It follows the reading rather than leading it.** The strip scrolls itself to whichever month the reader has scrolled the list into, so the bars are always about what is on screen. It can be pushed by hand too, and it moves a month at a time : half of one beside half of the next is a comparison nobody asked for.

**The day at the top of the list is the coloured bar.** A dot over it, a panel behind it, a width of its own : each of those would add a thing to a chart that is already thirty things, and colour adds nothing. Every bar keeps its width and its place, so nothing moves and nothing changes shape as the reader crosses from one day into the next. The turn is felt as well as seen, once the reader has actually moved : the first day a list settles on is not a change, and a buzz on opening a screen is a buzz nobody asked for.

**The scale is the busiest day of every month offered, not of the month on screen.** Scaling each month on its own would draw a dead fortnight in August exactly as tall as a general election, and a chart whose scale moves under the reader lies for free.

**A day is a local day.** A reader in Paris opening this at one in the morning is still looking at yesterday's wire, and a chart that disagrees is a chart about a timezone rather than about them. SQLite is handed the reader's own offset and does the grouping ; a month of a busy corpus is tens of thousands of rows and all that is wanted from them is thirty-odd integers.

**The glass is the ground, not the bars, and finding that out took measuring rather than reasoning.** Thirty bars each made of glass does not work at this size. Glass shows what is behind it, and at the head of a page that is white paper, so an untinted bar and a white bar alike read as nothing at all : counted, not one pixel of a bar differed from pure white. Tinting them fixed that and brought its own trouble, `.regular` glass carrying a shadow apiece that pooled into a grey wash across the strip, forty thousand grey pixels taking the paper down to two hundred and thirty-six. `.clear` glass, the variant meant to be laid over content rather than to float above it, left fifty, but nothing else touched the wash : a `GlassEffectContainer` only softened it, and a `shadow` of one's own added after the effect did not draw at all.

So the strip stands on one piece of glass, shaped like the pills the front page pins its subjects on, and the bars are plain shapes drawn on it in the page's own ink, which inverts with the page : dark on the light material, light on the dark. The glass goes behind them rather than around them, since it lends its vibrancy to whatever it holds, which is right for the label on a pill and wrong here : held, the ink came back a light grey. With no shadow left to merge there is no container, and so no `glassEffectID` : a container hands its tints out by position unless every shape carries an identity, which drew the coloured bar five columns from the day it belonged to.

**Pinned is not the same as in front.** A section header pinned in a lazy stack is drawn under the rows unless it is lifted, and a headline crossing the chart was drawn on top of it.

## Collections, in squares

What the reader kept is shown as a grid and not as a line. A list is right for things read one after another, which is what the stream is ; what was kept is not read in order, it is gone back to, and going back to something means finding it. A square carries a picture, and a picture is found faster than a line of type. It is the shape Photos gives the same idea, which means a reader has met it before.

**The page is in three parts, and their order is the argument.** What the reader marked comes first and wears no heading, a heading over two squares everybody has being a heading that says nothing : favourites is what they starred, notes is what they wrote on. Then what they made themselves, under their own name. Then the months, which fall out of when an article arrived and cost nobody any tidying.

**The middle band is the albums.** A band with nothing in it is not drawn at all, its heading included, so a reader who has made no collections is not shown an empty shelf with a label on it. The way to make one is a `+` in the leading corner, beside the sources : it is there whether the shelf exists or not, which is what lets the shelf be absent. It was a dashed square at the end of the band first, in the manner of Photos, and that square was the reason the band could never be empty ; between the two, the corner won, since a page with two ways to do one thing has spent a square saying it twice.

A collection is a tag, which was the plan before it was a need : section 4 says a tag applies to an article or a feed, and `tag` and `tag_binding` have been in the schema since v1. Everything lives under a `collection/` root, so a tag and a collection of the same name stay two things, and a name carrying the separator is refused rather than allowed to invent a level. Renaming keeps what is in it ; throwing one away keeps the articles, a collection being a way of looking at articles and not a place they are stored.

Filing happens from the article's own menu, as a submenu of toggles. It is a decision made in passing, and a page that had to be opened and dismissed for it would cost more than the decision is worth. There is nothing to keep or promote first : filing an article is one row saying so, and a filed article is never purged for the same reason a starred one is not.

**Two marks, two meanings, side by side.** The star is favourites ; the folder is the collections the reader made. They stand next to each other in the article's bar because they are the two things done to an article worth keeping, and they are not the same thing : one is a judgement about it, the other is a place to put it. Favourites was folded into the folder's menu once, on the theory that one list was simpler, and it was the opposite : it made the two marks two ways of doing one thing, and a reader who starred everything they filed would have said something they did not mean.

The bar holds three : the star, the folder, and everything else. A fourth wants checking before it goes in, because iOS folds what does not fit into an overflow of its own, and an action inside an overflow inside a menu is an action nobody finds. That is not a hypothetical here.

Notes and the months are in neither menu. An article joins notes by being written on and joins a month by being kept : both are consequences, and a consequence is not a thing to choose. They are shown on the collections page and nowhere else.

**Everything a square knows, it knows from the article.** There is one row and no copy of it, so a count and its contents are the same question asked twice and cannot disagree. They did disagree, twice, while there were two stores : a count said two over a page showing one, because a discarded copy left its bindings behind, and unstarring an article emptied every collection it was in, because the star addressed the copy and throwing the copy away threw the filings away with it. Neither is expressible now. `docs/technical/marks.md` carries the whole of that argument.

**Grouping by newsroom was tried and taken out.** It made a band of squares nobody had asked for, between the two the reader had made and the months : a page of squares is a page a reader scans, and a scan is spoiled by the row that is there because it could be.

**A square is square.** Everything else on the page is set at three by two, which is the shape a photograph arrives in. A grid is a different argument : equal cells are what let the eye run down it, and a square is the only shape that stays equal in both directions. The mark of what the square holds is drawn under the picture rather than instead of it, so a cover that is slow or that never answers leaves no hole in the grid.

**A heading takes the colour of the mark beside it.** The live band is the one place on the page with a colour of its own, and the dot and the word are one mark : the word is set in the dot's colour at the quiet end of its pulse, so the dot stays the loud half and the pair reads as one thing. Both come from `LiveDot`, named rather than written twice, since two literals that happen to agree today are two literals that stop agreeing the first time one of them is changed.

## The page keeps itself up to date

**The window follows the store.** Every list used to be loaded by an explicit call after an action the window itself had taken, which works perfectly for what the window does and not at all for what it does not : a background refresh, a change arriving from another device through `CKSyncEngine`, an archive read in, a job finishing. All of those wrote to the store and nothing told the reader, so a window left open showed this morning's page until it was pulled down, or left and come back to.

`DatabaseRegionObservation` over the tables the interface is drawn from is what tells it now. This is the reason GRDB is here at all : `CLAUDE.md` says the package earns its place by replacing the connection pool, the migrator, the typed row decoding and the change observation the store would otherwise have to own, and the observation was the one of the four never used.

A region rather than a value : what is wanted is the news that something moved, after which the window reads back what it happens to be showing. The machinery's own tables are not watched, `sync_state` and `archive_ingest` being where the synchronization writes down where it got to, and a window that reloaded every time a change token moved would reload constantly and show the same page.

**A burst settles before anything is read back.** Three hundred feeds refreshing is three hundred transactions and the window needs one reload. The stream keeps only the most recent tick, so everything arriving during the four hundred milliseconds of settling, and during the reload itself, collapses into the single tick that follows.

**Not the article list, while an article is open.** Opening one marks it read, and a list reloaded under it would drop that article out of the unread view the reader is about to come back to. The digest, the sidebar and the collections are read back either way ; the list waits until they are looking at it.

**And a clock, for what the store cannot know.** Following the store shows what has arrived ; nothing in it asks the publishers. A window open all day asked nobody anything, the only foreground refresh being the return to the front, and a Mac window that never leaves the front never returns to it. Every ten minutes it asks, which the politeness of `docs/technical/fetching.md` then decides per feed : most of those ticks find nothing due and cost one query.

**Pull to refresh stays, on the front page only.** It is no longer how the page keeps up, and it is still how a reader says now rather than soon : the clock is ten minutes and politeness may defer beyond it, Low Power Mode and an expensive network both suppress the background pass deliberately, and iOS may grant no background slot for hours. One place to say it is enough, and the front page is where a reader is when they wonder. The wire has none : it is a list of what has arrived, and what arrives reaches it on its own. A Mac has no pull at all and keeps the command, in the place a Mac keeps commands.

**There is no pull, on any page.** The page keeps itself up to date : it follows the store, so anything that arrives reaches it, and a clock asks the publishers what politeness allows. A pull on top of that buys nothing and costs something. A gesture that is always under the thumb invites being used, and a reader pulling a wire every few seconds is a reader their own reader has made anxious. That is the argument that settled it, and it is a better one than the mechanics.

The mechanics were bad too. SwiftUI holds the refresh control out until the work the gesture started returns, and the control's space was not always reclaimed when it retracted : the page stayed pushed down by exactly its height, with the large title still open, until anything at all touched the screen and forced a layout. Four attempts at the cause missed, and none of them could be reproduced on a simulator, where a synthesised drag never engages the control at all. Removing the gesture removes the fault with it, which is a poor way to fix a bug and a fine way to remove a feature that was not wanted.

**Asking is still possible, and now takes a deliberate act.** `Actualiser` sits in the reader's own menu, beside the other things they ask for, and keeps its `⌘R` on a Mac. It fetches every feed and groups what arrived ; the model's work carries on behind it, since those are resumable jobs and each headline appears as it is written.

## Pictures, and the marks beside them

**A hairline inside every picture's own edge.** A publisher's picture arrives at whatever contrast it was shot at, and one that ends in white sits on a white page with no edge at all : the line is what says where the picture stops.

**Inside, and not a ring around.** A ring outside is a mount, and a mount is a frame doing more than saying where the picture ends. Inside, the line is part of the picture's own edge and takes no room : nothing moves to make space for it. `strokeBorder` rather than `stroke`, since a stroke straddles the path and half of it would fall outside the clip, which is a line drawn at half its width and softer on one side than the other.

**A line, and not a material.** Glass was tried and taken out. At a point and a half it read as a band ; taken down to a hairline the regular material is a pale smear and the clear one is nothing whatever, measured at pure white against a white page. What is wanted is an edge, and an edge is a line. It is also hundreds fewer glass effects in a list somebody is scrolling, which are real resources and not free.

The separator's own colour rather than a white highlight. White is the glass idiom and it disappears on the picture that most needs an edge, which is the one ending in white on a white page ; the separator holds against both and turns with the appearance.

**A source's mark is round**, with the same hairline inside it. A favicon arrives as whatever square its publisher drew, dark on dark as often as not, and a round crop is what makes a column of them read as one column rather than as a row of unrelated stamps. The generic mark, for a source that serves none, keeps its bare glyph : an edge around it would make an absence look like a mark.

**A picture meets the line that says what happened.** Above a story's summary sit the subjects it is filed under and its headline, and a picture set level with a one-word rubric leaves the column ragged. It is aligned on the summary instead, through a `VerticalAlignment` of its own, so the text reads as one block with a picture beside it. A story with no summary has no such line, and the guide falls back to the top, which is where a picture belongs when there is nothing to meet.

**The pictures are decoded off the main thread, and were not.** The target builds with `SWIFT_APPROACHABLE_CONCURRENCY`, under which a `nonisolated async` function runs on its caller's actor rather than on the pool. Every caller of the image store is a view, so every caller is the main actor, so the ImageIO decode was happening on the main thread : one picture at a time, a few milliseconds each, for every row a reader scrolls past. A list that stops moving while it fills is the shape of that, and it is what the reader reported as the interface freezing.

`@concurrent` on the fetch is what takes it back to the pool. It never showed on a simulator, where a Mac decodes a photograph faster than a frame lasts ; it shows on a phone. The lesson is worth keeping rather than the fix : under approachable concurrency, `nonisolated` no longer means off the main actor, and anything expensive a view awaits has to say so.

## The reader's menu

One button in the same corner of every section, holding what the reader has decided. It sat in the digest alone at first, which made it the digest's menu rather than the reader's : what it holds belongs to the person and not to the page, and a thing that belongs to the person is in the same place wherever they are.

It is still not an account. There is no account and nothing to sign in to, and the face on the button is the reader's own picture rather than a sign that they are signed in to something. It is called `Réglages` in French.

It holds the subjects, the sites the reader is signed in to, the notices, and `Actualiser`, which is the only way to ask for a refresh now that no page has a pull.

It also holds `Forcer la synchronisation`, under `#if DEBUG` and nowhere else. The engine decides when to send and when to fetch and is right far more often than a button would be ; what that command is for is watching an exchange happen on demand while something is being built. It queues every record this device holds, which is the repair path and costs a few thousand records against a budget of three thousand, and that is why it does not ship.

The command to write the digest again was here and is gone, replaced by that one. Nothing in the interface asks the model to re-read a page it has already read : stories already filed are never re-read, which is what makes the page stable.

**The section is called `Collections`, not `Bibliothèque`.** A library is a shelf of books, and what this section holds is articles somebody put aside ; `Bibliothèque` was also the longest of the four names in a bar that has to fit four. `Collections` is what Photos calls the same idea for the same reason, which means a reader has met it before. The word outlived the thing : the library it was renamed from is gone from the store as well as from the bar, and `docs/technical/marks.md` says why.

**The bar's three marks are one family, and they had to be made one.** A tab bar fills its symbols itself, so every mark in the row arrives as its `.fill` variant : solid shapes with weight. `dot.radiowaves.left.and.right` has no filled variant, so it stayed a hairline drawing between solid ones, which is what unbalanced the row. The stream takes `tray.full` instead, which fills, and which is the mark the same view already wears in the sources list, since it is the same view. What is left is the front page's own stack of sparkles, a full tray of what has come in, and a folder of what the reader filed, all three drawn at the same weight.

**The sources came off the tab bar, which is now four sections and not five.** A tab names a place there is to read, and a folder tree is not one : it is something a reader touches when they are organizing, which is rarely, and the bar is better spent on reading.

They are not in the menu either, though they passed through it. They were the one thing in it a reader opens often, and a thing opened often is a button rather than a line in a menu : they sit in the leading corner, opposite the reader's own face, in each of the three sections a reader reads in. Search does not carry it, its bar belonging to the field, and a reader who is searching is not organizing.

The one thing that move could have broken is the first launch, where a reader who follows nothing had the sources tab in front of them and now does not. The front page says so instead : with no feed at all it offers adding one and importing an OPML file where the reader is already looking, rather than explaining what grouping is to somebody with nothing to group.

**The subjects screen is the other half of the pills.** A pill carries a subject of the day, where an opinion is formed and where saying it costs one press. The screen carries every subject there is, including those that have fallen off the page, so a reader who asked for less of something months ago can find it again and take it back : a preference nobody can find is a preference nobody can undo. Each row is a picker of three, down, nothing, up, rather than the pill's nudge by one : here the reader is choosing a side, and reading back three shades of the same side would be a control that says more than it lets them say.

**The face is the button.** A name and a picture, both optional, both the reader's own, kept in their own iCloud beside their other preferences. There is nowhere to send them : section 3 says there is no server, and a name typed into a feed reader is not an exception to that. What they buy is that a device the reader picks up looks like theirs, and that is the whole of it. The mark has three states, in the order a reader arrives at them : the picture they chose, the initials of the name they typed, and the generic face of somebody who has told the application nothing. The third is not a failure and is not nagged at.

The picture is scaled on the way in and never after. What comes out of a photo library is a photograph, twelve megapixels and four megabytes ; what is wanted is a mark twenty-six points across. It is resized once to two hundred and fifty-six pixels, re-encoded as JPEG so that a HEIC from a phone and a PNG from a Mac take the same room, and anything that still exceeds a hundred and twenty-eight kilobytes is refused rather than allowed to fill a store that holds one megabyte for everything. A face on a phone comes from the photo library, through the picker Apple runs outside the application, so nothing here ever sees the photo library and no permission is asked for ; a face on a Mac comes from the open panel, because a Mac reader offered a photo library would be offered the wrong drawer.

**Marking everything as read left the sections a reader lands in.** It is a command about a list, and the two sections that had it are not lists of a thing to get to the end of : the stream is a wire and the collections are what was put aside. It stays where it means something, on a feed, a folder or the unread view, each of which is a list with an end. What takes its place in the corner is the reader's own menu, which is now the same one button in all four sections.

**A story is a `fil` in French, and a subject is a `thématique`.** Both English words translate naturally to `sujet`, and only one of them could have it. The first attempt gave it to the story and left the subject as `thème` ; that reads backwards, since `sujet` in ordinary French is exactly what a subject is, and it cost a round of the two being confused for each other in conversation before the naming was settled.

`Fil` says what a story is, several articles following one thing, and `thématique` is unambiguous where `thème` was merely unclaimed. The cost is that the stream section is called `Flux`, so `Fil` and `Flux` sit near each other ; they are different words for different things and the sections they name are never side by side.

## The day over the wire

**The glass arrives with the scroll, and the month narrows into it.** At rest the chart runs the whole width of the screen and wears no material at all : glass over nothing is glass doing nothing, a material's whole job being to say that something passes behind it. The first row to go under the bars brings it, and the month steps back into the column the rest of the page is set in as it comes. The two are one movement, driven by the reader's own scroll, and both go again when the page returns to the top.

A month is a picture of a whole month and reads better for having the whole width ; a piece of glass is a thing on the page and belongs within the measure like everything else on it. Uncovered, the chart steps out of the page's gutter with a negative inset of exactly its width, which is why that gutter is a named constant rather than a number written twice.

The offset is what is asked, not the rows : a row is a landmark and this is a question about a single point, the top of the content against the top of what is shown. Against a hair rather than against nought, since a scroll view rests at a fractional offset often enough and a glass flickering on and off under a still thumb would be worse than one that never left.

**An hour with nothing in it is grey, not absent.** Whether it has been and gone or has not happened yet, it keeps its place at the height of the shortest bar there is. The row stays a row, with a level floor an eye can run along, and the ink is kept for the hours something actually arrived in.

**It counts hours over a day, and not days over a month.** A month of thirty-odd bars says which weeks were busy, which is a fact about the press rather than about the reading : somebody looking at a wire wants to know what has come in since they last looked, and that is a question about this morning and last night. Exactly the hours the day has, which is twenty-three, twenty-four or twenty-five, since the day the clocks go back is twenty-five hours long and a chart that always drew twenty-four would put an hour's arrivals somewhere they did not happen.

**It is followed, never dragged.** The day it shows is the day the reader is in and the coloured bar is the hour they have reached, both read off the list as they scroll it. A second scroll of its own, on the same screen and at right angles to the first, would be two ways of moving through one page and a way of putting the two out of step ; the strip moves by being followed.

## The dateline

**The title of the page is the date.** Not the name of the section : the tab bar says that already, and a page that repeats its own label has spent a line saying nothing. A dateline says what the label did not, which is how old what follows is allowed to be, and it is where a newspaper puts it.

It is a large title like every other section's, so it shrinks into the bar as the reader scrolls into the page. It is spelled the way the reader's language spells it, with only its first letter raised : French writes `samedi 29 août`, and capitalizing every word would give `Samedi 29 Août`. It is read at each render rather than held, so a page left open overnight is not still yesterday's.

There is no refresh button. The page refreshes itself on returning to the foreground and on a pull, which is every way a reader asks on a touch screen. A Mac has no pull, so it keeps the command in the toolbar, on the key a Mac expects.

## Subjects, not periods

The page opened on a day, week and month selector. A period is a question about the calendar, and nobody watching a subject asks it : they ask what is happening, and then what is happening about one thing. So the selector is gone and the pills are the subjects the model found across the page, the first of them being the front page itself.

They are pills rather than type because they are a filter that changes what is below, which type would understate, and because there may be six of them and they have to scroll. The row scrolls horizontally, hides its indicator, and disables scroll clipping so a pill's glass is not shaved at the edge of the column.

They stay at the head of the page as it scrolls, as a pinned section header. `safeAreaBar` was the first attempt and lays out under a large title while drawing itself two hundred points lower ; a pinned header is where this one belongs anyway, at the head of what it filters. A filter that leaves the screen is a filter a reader has to scroll back up to change.

**A long press on a subject says more of this, or less of this.** It is a `Menu` with a primary action rather than a `Button` with a `contextMenu` : the tap does the tap, the long press opens the menu, and both are the control's own business. The context menu never fired at all over the pill's glass, measured on the simulator with a real long press, and a menu also gives the whole capsule as the target instead of the text inside it. The Mac keeps a context menu on top, since right-clicking is how a Mac says the same thing.

Every pill keeps one weight, chosen or not. Bolder when chosen made the pill three and a half points wider when chosen, and every pill after it moved as the reader tapped.
 A subject is the only thing on the page general enough to hold an opinion : an article is one article and a story is one event, and a preference about either would be a preference about something that will not happen again. The score starts at nought, moves by one, and stops at three either way : past that the reader is no longer expressing a preference, they are hiding things from themselves, and the front page is not the place to do that.

A pill carries an arrow only when something was said about it. A row of arrows on every pill is a row of arrows nobody reads.

The section under the pills is called `Stories`, never `Front page` : that is what the pill already says, and a page does not need to name itself twice. Narrowing to a subject renames the section to the subject, and leaves the other pills on screen : take them away and the way back is a button that is no longer there.

Where there is no model there are no subjects, and no pills at all. The front page is entire on its own, which is what section 14 asks of every path that touches the model.

**What the model wrote wears `sparkles`, and not `apple.intelligence`.** The Apple Intelligence symbol says which model, which is more than a generic shimmer says, and it was tried. It is a restricted one : it sits in `symbol_restrictions.strings` beside `apple.logo`, `siri` and `safari`, the set Apple reserves for depictions of its own products and features. It renders perfectly in a third-party application, so the objection is a licensing one rather than a technical one, and it is not worth carrying to a submission for the sake of a glyph. `sparkles` carries no such restriction.

## What the model wrote, and how to refuse it

A story's name and its one line are written on the device by the system model. The row says so, with a mark, and the story page explains in one sentence what was done and offers to fall back on the article's own headline. Section 14 of the specification requires the first ; the second is what makes the first honest, since a label the reader cannot act on is decoration.

Where there is no model, or where it refuses, the story is named after its most central article. The page is entire either way.

## What 2026 asked for, and what was ignored

The year's design writing converges on cognitive clarity over sensory richness : calm surfaces, fewer simultaneous signals, motion used as information, artificial intelligence made visible, optional and explainable rather than ambient. That is the page above, and it is also why the digest states its evidence out loud : four rooms, five articles, this shape of arrival, seventeen minutes ago. A story that cannot say why it is on the page does not deserve to be.

What the same writing recommends and Flong does not do : ambient gradients behind content, a bento grid of unequal cards, an assistant panel, and depth for its own sake. They are all ways of adding sensory richness to a screen whose whole job is to be read.

## Accessibility

Dynamic Type carries the layout : the measure is a maximum, not a fixed width, and every row grows. Icon-only controls carry a label. The facts line is combined into one accessibility element per story rather than read as six fragments. The live dot never conveys its meaning by motion or colour alone, since the section header next to it says the same thing in words.
