# The interface

Flong is meant to be a tool for watching a subject, not another aggregator. An aggregator is a list of what arrived ; a tool for watching says what is happening, who is saying it, and whether it is still moving. The interface exists to make that difference visible, and every decision below follows from it.

## One column

The three-pane layout is what every reader ships, and it is a poor fit for reading. Two columns of chrome around an article are two columns of not reading, and on iPhone the third pane never existed anyway. Flong shows one thing at a time : the digest, then a story, then an article, each pushed onto a stack, each with its own way back.

Sections keep their own stack, so leaving the library in the middle of something and coming back lands where the reader was, not at the beginning of everything.

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

On macOS the same five sections become a sidebar, through `tabViewStyle(.sidebarAdaptable)` : there is no bar to minimize on a Mac, and a window is already out of its own way.

## Pictures

An editorial page without pictures is a page of grey, and a page where every picture is the same size is a list. So there is a hierarchy of exactly one : **the first story runs its picture across the column**, in a band rather than a square, above a larger headline ; everything below it keeps its picture to a square at the side. That is how a front page has said what matters for two centuries, and it costs one line of code to say it.

Sixteen by nine across a column of six hundred and eighty points is a picture four hundred points tall, which is one story per screen and a front page that says nothing at all. The band is `Editorial.bandAspect`, two point two to one : the same picture, and the rest of the page given back.

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

## The wire

The section beside the digest shows everything, newest first, read or not. A queue is a thing to get to the end of, and a reader watching a subject is not trying to finish anything : what they want is to see what came in, and where they left off.

**A read article is marked, not diminished.** It carried a blue dot when unread and a lighter headline when read, which made half the page look stale and quietly said that a story already opened was worth less. Every headline keeps one weight and one colour now, and a read one ends in a small tick : at the end of the words rather than beside them, where the reader stopped reading, costing the row no width. The section carries no count either. A number that only ever grows is a debt, and nobody owes their feeds anything ; the sources list still counts what is unread, for whoever wants to know.

It is broken by day, in the same kerned uppercase as the front page's sections. A long scroll with no landmarks is one a reader loses their place in, and the day is the landmark.

Unread on its own is still a view, in the sources list, for whoever wants a queue.

## The reader's menu

One button in the digest's toolbar, holding what the reader has decided. Not an account : there is no account, nothing here belongs to anyone but the person holding the device, and a person icon would promise a profile that does not exist. It is called `Réglages` in French for the same reason.

It holds the subjects, and the command to write the digest again, which had been buried at the foot of the sources list where it never belonged : the sources list is for the state of the machinery, and asking the model to write again is the reader's own decision.

**The subjects screen is the other half of the pills.** A pill carries a subject of the day, where an opinion is formed and where saying it costs one press. The screen carries every subject there is, including those that have fallen off the page, so a reader who asked for less of something months ago can find it again and take it back : a preference nobody can find is a preference nobody can undo. Each row is a picker of three, down, nothing, up, rather than the pill's nudge by one : here the reader is choosing a side, and reading back three shades of the same side would be a control that says more than it lets them say.

**`sujet` is a story in French, so a topic is a `thème`.** The story page is titled `Sujet` and the front page's second section is `SUJETS` ; calling the topics `Sujets` as well would have had `Typographie, 1 sujet` mean two different things in one line.

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

## What the model wrote, and how to refuse it

A story's name and its one line are written on the device by the system model. The row says so, with a mark, and the story page explains in one sentence what was done and offers to fall back on the article's own headline. Section 14 of the specification requires the first ; the second is what makes the first honest, since a label the reader cannot act on is decoration.

Where there is no model, or where it refuses, the story is named after its most central article. The page is entire either way.

## What 2026 asked for, and what was ignored

The year's design writing converges on cognitive clarity over sensory richness : calm surfaces, fewer simultaneous signals, motion used as information, artificial intelligence made visible, optional and explainable rather than ambient. That is the page above, and it is also why the digest states its evidence out loud : four rooms, five articles, this shape of arrival, seventeen minutes ago. A story that cannot say why it is on the page does not deserve to be.

What the same writing recommends and Flong does not do : ambient gradients behind content, a bento grid of unequal cards, an assistant panel, and depth for its own sake. They are all ways of adding sensory richness to a screen whose whole job is to be read.

## Accessibility

Dynamic Type carries the layout : the measure is a maximum, not a fixed width, and every row grows. Icon-only controls carry a label. The facts line is combined into one accessibility element per story rather than read as six fragments. The live dot never conveys its meaning by motion or colour alone, since the section header next to it says the same thing in words.
