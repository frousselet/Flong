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
| `headline` | the theme's own face, semibold | The one line a theme is allowed to speak in. It stays apart from everything under it without a single line of chrome. |
| `standfirst` / `metadata` | sans, in every theme | A theme gets out of the way under the headline : prose reads best in a column face, and the facts under a story are for the reader who asks rather than the one who scans. |

The measures live in `Flong/Support/Editorial.swift` and the faces in `Flong/Support/Theme.swift`. A screen that needs a fifth spacing value is a screen that has gone wrong.

Section headers are uppercase, kerned, secondary, and a hairline rule sits above each row. That is the whole vocabulary. No card, no box, no shadow, no glass in the content.

## Three themes, and what a theme reaches

The headline face used to be serif and nothing else, which was a decision about what a page is, taken on the reader's behalf. It is now one of three, and the three are opinions rather than permutations of a typeface menu :

| Theme | Faces | Paper |
| ----- | ----- | ----- |
| `Défaut` | Serif headlines over a sans body | The system's own |
| `Papier` | The same faces | Warm cream, warm near-black at night, every colour in it warm and pulled back from the contrast a screen defaults to |
| `Solarized` | Monospace headlines over a sans body | base3 and base03, base01 and base1 for the ink, violet for a control |

**Three, and three is the number.** Past three they stop being opinions.

**Two faces for the three of them.** `Défaut` and `Papier` are set the same and are told apart by their colours alone ; only `Solarized` changes the headline face as well. That is the right shape rather than a shortfall. Serif headlines are what this application was set in before there was a choice, for the same reason the whole page is set the way it is, and a reader who asks for warm paper is asking about the paper. A theme obliged to change the face in order to justify being a theme would be changing it for that reason and no other.

**The face is the loud half.** A reader can name a theme's colours after a while ; they tell the face apart in the first second, and it is what says whether this is a place where things are read or a place where things are managed. So the panel sets each theme's name in that theme's own headline face : a list of three words in one face asks the reader to remember what `Solarized` looked like, and a specimen asks them to remember nothing. The line under each name says what the colours do, which is the half a row cannot show.

**`Papier`'s accent is dark and barely coloured, rather than cool.** It began as a terracotta, `#9C5B33`, half saturated and at the lightness of a photograph, and the glyphs in the bar read as brown objects rather than as things that can be pressed.

The instinct is to cool the hue, and it is wrong : a blue accent was tried and it took the theme apart, the one thing `Papier` is for being that everything on the page belongs to one warmth. The trouble was the chroma, and the lightness that let the chroma speak. Taken down to where ink lives and to a third of its saturation, `#5F4533`, the same warmth reads as ink that happens to be warm.

At night it goes the other way, since ink on a dark ground is the light thing : the same warmth lifted to `#B98D70`, and left a little more of its colour than the light one keeps, since a desaturated tone on a dark ground reads as dust. Kept well clear of the cream the page is set in, so that a control is still a control and not a slightly different word. The live dot stays brick red in both, being the one thing in the application that is meant to be the loudest.

**A theme speaks in the headline and gets out of the way underneath it.** The standfirst, the body of an article, and everything the application says about one are sans in all three. A newspaper sets its headline in the display face it paid for and its columns in whatever reads best down a column, and it has never set both in the same : what is left to a theme is the one line that is glanced at, which is the line a face is for. `Papier` set its standfirsts and its article bodies in serif to begin with, and a page of prose in a display face is a page that is looked at rather than read. `Défaut` went the other way and set even its headlines in sans, which threw away the distinction rather than misplacing it.

The metadata is part of that, and doubly so : it is the application's own voice, and a theme that set it in the headline's face would have thrown away the one distinction the typography exists to make. A monospace caption under every story would also be the loudest quiet thing on the page.

**`Défaut` states no colours at all, and that is what it means.** It is the system's appearance, so it is left to the system : a theme that restated the system's colours as literals is a theme that stops following them the first time the system changes one, or the reader turns the contrast up. `Theme.paints` is what says so, and the painting modifier does nothing under it. The one place `Défaut` does state its six colours is the rendered article, which is a web page and has no system colours to inherit ; they are the values the stylesheet has always carried.

**Light and dark are not themes.** Each of the three states both appearances and follows the device, which is why `Palette` is asked for one appearance at a time and why a test refuses a theme whose two papers are the same colour. The rendered article states both at once, in a `prefers-color-scheme` block : the web view is handed a document and cannot be handed another one when the reader turns the lights off.

### Where it is painted

The theme goes into the environment once, at the outermost modifier of the window, so that every sheet, alert and panel is inside it. The order is the whole of it : a modifier written later is the outer one, and a value reaches what is inside it, so the painting written outside the value that says what to paint reads the default for ever.

The paper itself is laid in three places, and each is a place the system would otherwise lay its own :

- **Inside each navigation stack**, on the page rather than around the tab view. A navigation stack draws the system's background behind whatever it is showing, so a colour painted on the window outside it changed every face and left the page white.
- **At the root of every sheet.** A sheet inherits the environment and therefore knows its theme, but it is a surface of its own : a background on the window behind one stays on the window behind it.
- **On the rows of a list**, by `themedRows()`, said on the list itself. A row's ground is the one thing a form's surroundings cannot state on its behalf, and the system's white card on warm paper is the brightest thing on the screen and the only thing in the panel out of theme.

The ink is set once, as the foreground style, and everything follows from it : a view asking for `.secondary` is asking for less of whatever the ink is, so the whole application follows without a screen having heard of a palette.

**`Solarized`'s accent is violet, not the blue everybody uses.** The palette has eight accents and the light paper rules out most of them. Yellow, green and cyan all sit near three to one against base3, which is a glyph one has to look for. Red, orange and magenta are the colour the live dot already is, or near enough that a row of controls reads as an alarm. That leaves blue, which is what Solarized itself reaches for and which is the weakest of the four survivors at 3.4 to one, and violet at 4.1, which is a control one can see. Violet is as much the palette's own as the blue was, so nothing is borrowed from outside it.

At night it is the same violet raised in lightness, hue and saturation untouched : against base03 the stated violet holds at 3.4 to one, which is the floor rather than a margin, and `#8B8FD0` is 5 to one and still recognizably the colour the light page uses. This is the one place Solarized's own claim, that its eight accents hold against either ground, is not quite taken at its word.

| Accent | On base3 | On base03 |
| ------ | -------- | --------- |
| yellow | 3.0 | 4.7 |
| orange | 4.3 | 3.3 |
| red | 4.3 | 3.3 |
| magenta | 4.2 | 3.3 |
| **violet** | **4.1** | **3.4**, lifted to 5.0 |
| blue | 3.4 | 4.1 |
| cyan | 2.9 | 4.8 |
| green | 3.0 | 4.7 |

### A tint stops at the edge of a photograph

Glass decides what to draw from what is behind it. That adaptation is the whole reason the controls on an article may float over a picture nobody chose, and it is the first thing a theme breaks : a tint is an instruction, an instruction overrides the adaptation, and the cross over a dark red photograph came out warm brown on dark red, which is a way out the reader cannot find.

So the accent reaches the article's bar only where the bar has the application's own paper behind it. Where the page has a lead running under the controls, the tint is handed back with `tint(nil)`, and the glyphs go back to flipping between dark and light with the picture, exactly as they do under `Défaut`. `Theme.accent(in:)` answers `nil` for that case as it does for the standard theme, which is the same answer for the same reason : the system is better placed to decide than the theme is.

The rule generalizes and is worth stating as one : **the theme paints what the application drew, and hands back anything drawn over something it did not choose.** A photograph belongs to a publisher, its colours are unknown until it has been fetched, and nothing decided months earlier in a palette can be right over all of them.

### What a theme does not reach

**The navigation layer stays the system's**, which is the same rule as the one above about Liquid Glass. A section's large title and the tab bar's labels are drawn by the system and take the system's colour ; neither `foregroundStyle` nor a styled `Text` passed to `navigationTitle` reaches them, and the only thing that would is a global appearance proxy, which is mutable state shared with every bar in the process, does not answer to a theme changed while the application is running, and has no macOS counterpart. So the dateline over the front page is the system's black on `Papier`'s cream, deliberately, and the application's own page begins underneath it.

## Liquid Glass belongs to the navigation layer

Apple's guidance for the 2026 material is explicit : glass is the layer that floats **over** the content, and glass must never sit on glass. Both halves matter, and the second one is easy to break by accident.

Flong broke it once. A hand-rolled floating bar in `safeAreaBar(edge: .bottom)`, drawn with `glassEffect`, collided on iPhone with the system search field, which is also glass : two blurred capsules overlapping, each refracting the other. The fix was not to tune the material but to delete the bar. The sections are a system `TabView`, the search tab carries `role: .search` so the system puts search where the system puts search, and `tabBarMinimizeBehavior(.onScrollDown)` gets the bar out of the way when the reader scrolls into something.

The application draws glass of its own in three kinds of place. The first two are the same rule rather than exceptions to it ; the third is an exception, and is admitted as one.

**The subject pills at the top of the digest** are controls floating over the page, which is the layer the material is for, and the row sits in the content and scrolls away with it rather than pinning itself under the tab bar, where it would be glass directly under glass.

**The credit in the corner of a picture** is the other case, and it is not a control. It is the one thing on the page that has to stay readable over an image nobody chose, and text laid straight on a photograph is unreadable on half the photographs there are. The usual answer is a scrim, which is a dark band across a picture the reader came to look at ; a pill the size of a name takes what is under it and leaves the picture whole around it. It is a handful per screen rather than one per row, which is what the hairline edge of a picture refused glass for.

**The danger zone at the foot of the reader's panel** is the exception, and it is one place in the whole application. The material is used there to say danger rather than to float over anything : the card leaves the grouped background the rest of the panel sits in, which is exactly the point, since a row that looks like its neighbours is a row that is pressed like its neighbours and this one deletes everything the reader has. It is admissible because it breaks neither half of the rule in practice : the form under it is not glass, so no glass sits on glass, and there is one card, not a pattern.

**Tinted at a third and not at full strength.** Red glass at full tint stops being glass : it is a flat red block, nothing of the page shows through it, and the solid red button it holds disappears into it. At a third the material does its own work, the heading and the sentence keep the contrast they need in both appearances, and the button stays the strongest red on screen, which is the right way round for the one control in the card. The warning mark is the red thing in the heading and the words are not, since a title in red on a red wash is a title read with effort.

Everywhere else the glass on screen is the system's.

On macOS the same four sections become a sidebar, through `tabViewStyle(.sidebarAdaptable)` : there is no bar to minimize on a Mac, and a window is already out of its own way.

## Pictures

An editorial page without pictures is a page of grey, and a page where every picture is the same size is a list. So there is a hierarchy of exactly one : **the first story runs its picture across the column**, in a band rather than a square, above a larger headline ; everything below it keeps its picture to a square at the side. That is how a front page has said what matters for two centuries, and it costs one line of code to say it.

**The type is a step up as well, and it had to be a real one.** The lead ran at `title2` over a page set in `title3`, which is twenty-two points against twenty : a difference a reader cannot see is a difference that is not there, and a lead announced by its picture alone is a picture with an ordinary story under it. It takes the next step of the scale in both, `title` over `title3` and `body` over `subheadline`. Steps of the scale rather than sizes in points, so the whole of it still follows Dynamic Type.

Every picture is shown at three by two, lead and thumbnail alike. That is what a camera takes and therefore what a publisher's picture already is : any other ratio is a crop, and a crop is a decision about somebody else's photograph. One ratio for the whole page rather than a band above and squares beside, since a column whose pictures are all the same shape has a rhythm and one whose pictures each have their own does not.

It is `Editorial.pictureAspect`, named once. Across a column of six hundred and eighty points a lead runs to four hundred and fifty, which is most of an iPad screen : the trade is fewer stories at a glance in exchange for pictures nobody has cropped.

Beside a picture on a phone the facts line runs out of room, and a line that wraps to hyphenate `rédac-tions` is worse than a line that says less. `ViewThatFits` drops the sparkline first, then the article count : what survives is who is talking and when they last did, which is the irreducible part.

`AsyncImage` is not used. It keeps no decoded image, so scrolling back up decodes everything again, and it decodes at full size, so a two thousand pixel photograph is unpacked whole to fill a sixty four point square. `ImageStore` makes the thumbnail straight from the encoded bytes with `ImageIO`, which is faster and an order of magnitude cheaper in memory, and keeps the result at the size it was asked for.

A picture occupies nothing until it has something to show, and nothing again if the address turns out to be dead : a grey rectangle where a photograph failed is worse than no photograph, and a page of them looks broken. It is decorative and hidden from VoiceOver, since feeds almost never carry alternative text and reading a headline out twice helps nobody.

## The colour of a picture, at the top of its page

A front page is one photograph and everything else set around it, and the picture gives the page its temperature before a word of it is read. `PageWash` is that, on a screen : the top of the digest, the bar over it and the dateline in it are washed in the colours of the story the page leads on, and the colour is spent by the time the picture that gave it comes into view. A wash still going at the photograph would be a tinted photograph rather than a lit page.

**A story's own page asks for the same thing with its own picture**, which is the very one the row that was tapped was carrying : the page opens in the colour the reader pressed, and the colour carries across the tap rather than starting again in white. The photograph is at the top of that page rather than a screen down it, so the same distance carries the colour beside the picture and runs out around its foot. That is the same idea from the other end : the light comes off the picture and stops where the picture does.

**Three bands and not one average.** A photograph averages its sky into its ground and comes out the colour of neither, which is why `ImageStore.average(of:)` is used for a favicon and would be useless here. The picture is resampled to a column of three pixels, top, middle and foot, and the page takes them in that order : the light in the picture at the top of the screen, what the picture is of where the page begins, and its foot fading into the paper.

**A photograph's own colours are not a background.** A night shot is nearly black and a snowfield nearly white, and either laid behind the dateline is a grey page or no colour at all. What is kept is the hue and the fact that there is one. How light it is stays the page's decision, pale on white and deep on black, moving within a narrow window so a dark picture still gives a slightly deeper page than a bright one. The saturation is lifted rather than floored, since a band is already a mean and means are duller than what they average : lifting leaves a genuinely grey picture grey, which most photographs of a press conference are, where a floor would invent a hue out of the noise in the last digit of a mean.

**It is laid in the content and rises above it.** The colour is wanted under the bar most of all, and the page's own content begins below the bar : a wash starting at the content would draw a hard edge across the screen at exactly the height a fade exists to make invisible. So it is drawn taller than the tallest bar the three platforms draw, held at full strength over all of that, and offset up into it.

**A gradient has two ends and both of them have to be nothing.** It began at full strength above the bar, which is an edge, and the edge was hidden where nothing could reach it. A pull to refresh reaches it : the gesture pushes the whole page down by a couple of hundred points, the wash goes with it, and the edge that had been kept out of sight came out under the bar with a slab of flat colour beneath it. The colour now rises out of nothing over three hundred points before the full-strength band begins, so a pull reveals the fade rather than the edge, and a pull long enough to reach the top of it finds nothing at all, which is the point. In the content rather than behind the scroll view, so it scrolls away with the head of the page it belongs to instead of staying on as chrome, and at the width of the window rather than of the column, since the page holds its type to a measure and light is not held to anything.

**Under the standard theme and no other.** `Papier` and `Solarized` state what the page is printed on, and a wash over either is a second opinion about the paper. The standard theme states nothing, which is the whole of what it means, so it is the one page with room for a picture to say something. It is also the only way the page reaches the bar at all : *What a theme does not reach*, above, records that a section's large title is drawn by the system in the system's own colour and that nothing short of an appearance proxy changes it. The type stays the system's ; the ground under it does not have to.

**And nothing whatever at increased contrast.** It is gentle enough to leave the largest type on the page legible over it, and it is still something between that type and the paper, which is the thing increased contrast is a request to stop doing.

**Unlike a mark's tint, the wash fetches.** `ImageStore.tint(at:)` answers from what is already decoded and never waits, because a pill is drawn the instant an article opens. The wash is wanted above the row that carries the picture and usually before that row has been built at all, so there is nothing to answer from ; it decodes the picture at sixty four pixels, which is ample for something about to become three, and from the bytes already in the cache wherever the picture has been shown.

## The mark of a publisher

A list of articles is a list of names, and names take reading. A mark is recognized before it is read, which is the whole of what a favicon is for. It stands beside the publisher's name on every article row, at the head of an article, and once at the head of each group in the sources list.

**It belongs to the publisher and not to the feed, and so does the name beside it.** A row used to carry the title of the feed an article arrived through, which is how a reader following three desks of one paper met `Le Monde - À la Une`, `Le Monde - International` and `Le Monde - Sport` down one page and had to work out that they were one paper. The desk is a detail of how the paper publishes ; who wrote it is what the reader wants. The desks are still named in the sources list, which is where a subscription is managed and where the distinction is the point.

**One favicon per publisher, asked for once.** A favicon is a property of a site, not of a file served from it : a paper drew one logo, and asking for it once per desk is six requests to say one thing, six entries in the cache and six chances of one of them coming back different. `SourceIdentity` is resolved once per group and is what the address is worked out from, so every row of that publisher wants the same picture and the store answers all of them from the one fetch.

The name is looked up on the row rather than carried on the article, which is what lets a publisher the reader renames be renamed on every row at once, without five hundred rows being read back out of the database. It rides in the environment, since every list in the application asks for it and threading a dictionary through five screens would be five signatures carrying something none of them is about.

On the digest the mark stands **in place of the count of rooms**. `4 rédactions` is a number the reader has to turn back into rooms ; four marks are the rooms, and they say which ones, which is the question behind the number : a story every paper is running and a story only the trade press is running are not the same story. Four are shown, and a fifth room becomes a `+1`. The count survives for anyone listening to the page rather than looking at it, since the row of marks carries it as its accessibility label. A story two desks of one paper ran draws one mark there too, for the same reason it counts as one room.

Three addresses are tried, in order : **what one of its feeds states**, since the publisher chose it ; **`apple-touch-icon.png`**, a well-known path, square by convention and large enough to stay crisp where a sixteen pixel favicon would not ; and **`favicon.ico`**, the oldest well-known path and still the most widely served, since browsers ask for it whether a page mentions it or not. The well-known ones hang off the root of the site, never off the page a feed happens to point at.

Nothing is asked for until a row is on screen, and what comes back is kept on disk, so a publisher costs one request rather than one per appearance. One that answers none of the three wears the generic mark : a list must keep its column of marks whether a publisher serves one or not, which is the one place a picture does not simply vanish when it fails.

## Every picture is credited

**A picture on the page belongs to somebody, and the page says who.** Only the address is ever stored : the file stays the publisher's and is asked for from their own server when a screen shows it, so the least a screen owes them is a name saying whose it is. A story is several rooms and the picture is one room's, which the marks beside the headline do not answer.

**The name, in the corner of the picture, on a pill of glass.** A caption was set under the picture first, reading `Image via Le Monde`, and it cost a line of the page under every picture on it to say what a name already says : a name in the corner of a photograph is a credit by the oldest convention there is, and nobody has to be told what it is doing there. The words survive as the accessibility label, where there is no corner to put a name in.

**Never a byline.** What Flong knows is the article the picture arrived with, and nothing else : the publisher may have credited an agency, a photographer or nobody at all, and none of that reaches a feed. A credit reading `Photo Le Monde` would attribute the picture to whoever happened to run it, which is a thing nobody here knows.

**Two sizes, and not one scaled down.** A credit is set against the picture it belongs to and not against the page : the pill that reads as a caption in the corner of a lead running the whole measure is a label stuck across the corner of a ninety-six point thumbnail. What stays constant is the share of the picture it takes, so the pill and the type inside it come down together — eleven points and nine, and the air around the name with them.

The lead's is a text style and grows with the reader's type size like everything else on the page. The thumbnail's is a fixed nine points, and that is the one place a fixed size is right : the picture is ninety-six points wide whatever the type size, so a pill that grew inside it would end up being the picture. What a reader who cannot read nine points needs there is the name read out, and the accessibility label is where it is.

**One line, and never cut.** A credit ending in `theguard…` credits nobody. Wrapping was tried and two lines fill most of a thumbnail and break the name across a hyphen, so the pill ends up being the picture that way too. Shrinking is what is left, and at the compact size it is reached only by a name longer than any address, which a thumbnail cannot hold legibly by any means.

It is shown at both sizes and on the story page, since a credit paid on the lead and withheld from the rest would be a courtesy shown to whichever publisher happened to be first that morning, and one that lasted only as long as a glance. **An article row carries none**, and does not need one : the row names the publisher under its own headline and the picture is that article's own, so a pill would say it twice.

## Motion that says something

Motion is either information or decoration, and decoration on a screen read every morning becomes noise by the second week. Three movements survive :

- **A story page, and an article, grow out of the row that opened them**, through `navigationTransition(.zoom(sourceID:in:))` and `matchedTransitionSource`. The motion says where the page came from, which is the one thing a push animation cannot. iOS and iPadOS only : macOS has no such transition and needs none.

  The article is presented rather than pushed, so the row it grows out of and the view it grows into are in two different trees, and the namespace has to be the window's. A screen that made one of its own matched nothing across that boundary and the article arrived from nowhere : the two lists that had a private one now take the window's, and it is passed in rather than declared, so there is one namespace in the application and no way to make a second by accident.
- **The rule under the period slides** from `Day` to `Week` rather than blinking on, through `matchedGeometryEffect`. It is the same object moving, so it moves.
- **The live dot breathes**, and stops breathing under Reduce Motion, where it becomes a plain dot that still reads as red.

Nothing else animates.

## The stream

The section beside the digest shows everything, newest first, read or not. A queue is a thing to get to the end of, and a reader watching a subject is not trying to finish anything : what they want is to see what came in, and where they left off.

**A read article is marked, not diminished.** It carried a blue dot when unread and a lighter headline when read, which made half the page look stale and quietly said that a story already opened was worth less. Every headline keeps one weight and one colour now, and a read one ends in a small tick : at the end of the words rather than beside them, where the reader stopped reading, costing the row no width. The section carries no count either. A number that only ever grows is a debt, and nobody owes their feeds anything. The sources list counted what was unread and does not any more, for the same reason : what it says beside a publisher now is how many articles they have given the reader, which is a fact about the publisher rather than a tally of what is owed. The views above the sources carry no count at all, `Non lus` being a number the reader meets everywhere else and `Tous les articles` beside one being the size of the corpus, answering nothing anybody asked.

It is broken by day, in the same kerned uppercase as the front page's sections. A long scroll with no landmarks is one a reader loses their place in, and the day is the landmark.

Unread on its own is still a view, in the sources panel, for whoever wants a queue.

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

**The page is in three parts, and their order is the argument.** What the reader marked comes first and wears no heading, a heading over the squares everybody has being a heading that says nothing : starred articles is what they starred, favourite sources is who they singled out, notes is what they wrote on. Then what they made themselves, under their own name. Then the months, which fall out of when an article arrived and cost nobody any tidying.

**The three favourites stand next to each other on purpose.** They are different judgements, and a page that put them at opposite ends would leave the reader to work out that they are not the same one : `Articles favoris` is what they starred, one piece at a time, `Sources favorites` is everything a publisher they singled out has ever served, and `Auteurs favoris` is everything a writer they singled out has signed, whichever paper it appeared in. One square holds four articles and another holds a morning's worth, which is the distinction saying itself. The first was called `Favoris` while it was alone on the page and could not be mistaken for anything ; the moment a second arrived, it had to say which favourites it meant, and the third is why none of them may ever go back to the short name.

**`Auteurs` is the odd square and is last for that reason.** Every other square on the page opens on a list of articles ; that one opens on a list of people, and the number under it counts names rather than pieces. A square saying `1 240 articles` that opened on eighty rows would have told the reader the wrong thing before they touched it. It is a directory, and a directory is a line and not a grid : a square is worth its space because it carries a picture, and a name has none. What a reader does there is look somebody up, which is what an alphabetical list with a search field is for. `docs/technical/authors.md` sets out why an author is a name matched exactly and never a person guessed at.

**A row is a name, the marks of the publishers it appears in, and a count.** The marks follow the name rather than the number, because they are an attribution and not a property of the row : `Claire Ancelin` with `Le Monde` and `Libération` after it is somebody the reader can place before they have opened anything. Four of them at most and no `+3` after, since they are a hint of where somebody writes and not an inventory of it, and the row already carries a number. They are the publisher and never the desk, and they are looked up in the same map every other mark in the application comes from.

**The favourites are a band of their own at the top of that list, and only when there are any.** A reader who singled out a dozen writers out of two thousand bylines would otherwise be hunting for them every time, which is the whole of what they were trying to avoid. With no favourites there is no heading either : one plain list, nothing labelled, exactly as this page draws a single band. The star is a button on the row and not only a swipe, since a swipe says nothing until it is tried and exists on one platform of the three.

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

## Searching, and what was searched before

The section is built the way Photos builds its own, because the shape is right and because the system already draws half of it. The reader arrives, the cursor is already in the field, the keyboard is up, and the page under it is about searching rather than about articles : what they looked for before, and above the keyboard the words the language is made of. Nothing there lists the whole stream, which the two sections beside it already do and which nobody opened the search tab to read.

**Arriving is not appearing.** A tab is built once and kept, so `onAppear` fires on the first visit and on no other, while a reader enters this section every time they tap the magnifying glass. The screen is told whether it is the current one and puts the cursor in the field whenever that becomes true, after a pause long enough for the system to have installed the field : focus asked for in the same turn lands on a field that is not on screen yet and is quietly dropped.

**Its head is every other section's.** A large title that shrinks into the bar as the reader scrolls into the page, the three panels in the leading corner and the reader's own menu opposite. It carried none of them once, on the theory that a reader who is searching is not organizing ; what that actually did was make one section of four look like a different application.

Keeping it took a modifier. The system hides the navigation bar for as long as a search field is presented, and this one is presented from the moment the reader arrives, so the page had no title, no panels and no corner at any moment anybody would see it. `searchPresentationToolbarBehavior(.avoidHidingContent)` is what asks for the toolbar to stay. The title is the noun in French, `Recherche`, where the field asks with the verb : English has one word for both and the catalog carries two.

**What is offered above the keyboard is a subject, not a syntax.** A field that offered `is:unread` and `tag:` was teaching its own grammar to somebody who had come to look something up. What is offered instead is what the feeds are full of this morning : `iPhone 18 Pro`, `Trump Iran`, `Budget 2027`. The digest already knows what that is, since grouping the reprints of one story is the whole of what it does, and `SearchSubjects` reads the subject out of each headline with `NLTagger` and with what capitals and digits say about a word. No model : section 15 says the path without Apple Intelligence always exists, and a suggestion that appeared on one device and not on another would be worse than none. Once the reader starts typing, the same subjects are filtered to whichever they are heading towards.

Three of them, stacked on their own lines rather than in a row. A subject is a phrase, phrases are not the same length, and a row of them is a row that scrolls sideways : a suggestion the reader has to go looking for is a suggestion that did not suggest anything. They wear Liquid Glass and sit against the field, close enough to read as what it is about to be filled with rather than as furniture belonging to the page.

**Three, always three.** More subjects are worked out than are shown, and what is kept is a queue. A subject the reader taps joins the searches above it and stops being worth offering ; a page that showed whatever was left would answer a tap by having one fewer thing to say, and the fourth steps into the place the first left instead.

**What was searched for is worth remembering.** A search screen that opened on nothing would have the reader work out again what they worked out yesterday. Ten are kept, newest first, matched without regard to case or to the spaces around them so that one search is one row. The whole row runs it again and the cross at the end drops it, two controls rather than a swipe, since this is a stack of rows in a scroll view and a gesture nothing announces is a gesture nobody finds. `Effacer` drops the lot, which is the one control a list of somebody's past searches owes them.

They travel with the other preferences, in the iCloud key-value store rather than in the record budget : what somebody looked for on the Mac is what they will look for on the phone. `docs/technical/erasure.md` covers what a reset does to them, which is the same thing it does to every other choice.

**Remembered on submit and on opening a result.** Results follow what is typed, so a reader who finds what they wanted never presses return, and a list fed by the return key alone would stay empty for exactly the readers it is for.

**What the sentence was read as is written above the results.** `LEMONDE.FR · 3 RÉSULTATS`, at the head of the list rather than pinned over it : it is a fact about the search, read once, and the foot of this page belongs to the field. A search that narrows itself has to say so, or a reader who sees a third of the articles they expected concludes it is broken. `docs/technical/search.md` sets out what does the reading.

**Two pages, not one page with two states.** A page of results is a list that scrolls. A page with no query has its furniture at the two ends of what is on screen, the searches at the top and the subjects at the foot, directly above the field. One layout doing both was a layout doing neither.

**And the subjects are content, not a bar.** Every bar this page could hang them from is the bar the system draws the search field in once the keyboard is up : `safeAreaInset`, `safeAreaBar` and a keyboard `ToolbarItemGroup` were each tried, and the first two draw behind the field while the third never attaches to a field a tab presents. What works is what Photos does : the page is as tall as what is on screen less the strip the field floats over, the searches sit at its head and the subjects at its foot.

**The subjects stand under the field, not in the column.** Everything else on the page is set in the measure the rest of the application is set in, and the field is not : it is the system's, and it stands closer to the edge of the window. Pills indented from the field they belong to read as furniture belonging to the page, so they take the field's own inset instead. That inset is measured, like the clearance below.

How much of that foot to keep clear is the other measured constant here, and it differs by keyboard. With the keyboard down the field sits inside the bottom safe area and the page already stops above it ; with the keyboard up it floats over the content, in no safe area at all, and nothing the page can ask says how tall it is. So the clearance is added in that state and only in that one, which is why the page listens for the keyboard at all.

## The sources, grouped by publisher

**There is nothing to make, and that is the whole change.** The sources list was a folder tree, and no screen in Flong ever let a reader plant one : the only folders that existed came out of an imported OPML file, so the organization on the page was somebody else's, inherited and untendable. A group is every feed served from one address, worked out from the addresses themselves. It is right the moment a subscription lands, it cannot go stale, and it does not survive the last of its feeds.

It is the same host the front page counts as a room, computed by the same function, so a paper with a feed per desk is one heading here exactly as it is one voice there. `blog.example.com` keeps a heading of its own : folding it into `example.com` would need the public suffix list and would file a paper and its unrelated blog together.

**A group is keyed by its address and shown by its name.** A reader who calls `lemonde.fr` `Le Monde` has renamed a heading in their list, not moved a feed anywhere ; the group sorts under `L` and the selection survives. Clearing the name puts the address back, which is what lets a naming be undone by somebody who no longer remembers the address. Only the names actually written are stored, one small row apiece, so a reader following three hundred feeds spends a handful of records and not one per publisher.

**The favicon stands at the head of the group and nowhere else in the list.** It is the publisher's, so six desks of one paper wearing six copies of one picture would be a column saying the same thing six times over. The rows under it are desks, named and nothing more.

**Every source is under a heading, the ones alone under theirs included.** A list where some rows are grouped and others sit loose is a list where the reader cannot tell in advance where a source will be. The heading is also the only place a group is acted on, so a group of one has to have one : it is a menu rather than a heading carrying a button, since a button beside every heading in a list of two hundred sources is two hundred buttons saying the same thing, and a heading that opens is learnt once. A chevron is what says it opens at all.

**A favourite source is a mark and nothing else.** It stars no article, moves no row to the top, and changes nothing the front page ranks : the reader was asked and said so. What it does is wear a small star where its name is read, and fill the square beside the starred articles on the collections page. A star on a source and a star on an article would be one gesture meaning two things, which is the mistake the article's own bar already refuses ; the words say which is which in both places, and `Sources favorites` is never `Favoris`.

**A favourite author is the same mark about a different thing**, and the only one of the three that crosses publishers : a reader follows a byline through whatever paper it turns up in, which no subscription can express. The second way in is the article's own overflow menu, where the opinion is actually formed - the reader has just finished the piece. It goes inside that menu and not beside the star in the bar : the bar holds three, and a fourth earns an overflow iOS makes of its own, which is the place nothing may go.

## The lead, and reading a page with the thing that ranks it

The front page runs its first story large, and the rest smaller. Which one is the lead was worked out by a computed property that each row called as it was built.

**A `LazyVStack` builds a row when it gets round to it**, which is not the pass that laid the page out and is not a pass that records what the page depends on. So a row compared a story from the array it had been handed against a lead worked out from whatever the store held at that later moment. After a refresh the two disagreed : every row answered `false`, the page ran with no lead at all, and nothing ever put it back, since nothing had recorded that the row depended on the lead in the first place.

**The page and its lead are read once, together**, into values the row closures capture. The story is from this array and the lead is from the same read of the same page, so the two cannot come apart however long the layout takes to ask for a row. It is the general rule behind the particular fault : anything a lazily built row is compared against has to come from the same read as the row itself.

## The page keeps itself up to date

**The window follows the store.** Every list used to be loaded by an explicit call after an action the window itself had taken, which works perfectly for what the window does and not at all for what it does not : a background refresh, a change arriving from another device through `CKSyncEngine`, an archive read in, a job finishing. All of those wrote to the store and nothing told the reader, so a window left open showed this morning's page until it was pulled down, or left and come back to.

`DatabaseRegionObservation` over the tables the interface is drawn from is what tells it now. This is the reason GRDB is here at all : `CLAUDE.md` says the package earns its place by replacing the connection pool, the migrator, the typed row decoding and the change observation the store would otherwise have to own, and the observation was the one of the four never used.

A region rather than a value : what is wanted is the news that something moved, after which the window reads back what it happens to be showing. The machinery's own tables are not watched, `sync_state` and `archive_ingest` being where the synchronization writes down where it got to, and a window that reloaded every time a change token moved would reload constantly and show the same page.

**A burst settles before anything is read back.** Three hundred feeds refreshing is three hundred transactions and the window needs one reload. The stream keeps only the most recent tick, so everything arriving during the four hundred milliseconds of settling, and during the reload itself, collapses into the single tick that follows.

**Not the article list, while an article is open.** Opening one marks it read, and a list reloaded under it would drop that article out of the unread view the reader is about to come back to. The digest, the sidebar and the collections are read back either way ; the list waits until they are looking at it.

**And a clock, for what the store cannot know.** Following the store shows what has arrived ; nothing in it asks the publishers. A window open all day asked nobody anything, the only foreground refresh being the return to the front, and a Mac window that never leaves the front never returns to it. Every five minutes it asks, which the politeness of `docs/technical/fetching.md` then decides per feed : most of those ticks find nothing due and cost one query. Five rather than ten costs the publishers nothing at all, a feed's own floor being fifteen minutes either way ; what it shortens is the wait between a feed becoming due and being asked, which is the only part of the delay the application controls.

**The clock acts first and sleeps after, and it is restarted rather than left running.** It slept first, so a window just brought back to the front waited a whole interval before anything was asked ; and a tick falling while the window was away was spent on nothing and cost another whole interval after it. Coming back to the application is itself a tick now, and the next one is counted from then.

**Fetching and showing are one thing, and used to be two.** The clock, the background refresh and the return to the foreground all fetched ; only a cold launch, the menu command and the nightly pass ever grouped what had arrived into stories. So a window left open watched its sidebar counts move while the front page itself sat unchanged, and a reader whose reader was plainly working still had to ask it by hand for the one thing they opened it for. Every automatic trigger goes through one entry point now, which fetches, groups and reads the page back ; grouping is a single query when there is nothing to group, so it costs a fraction of the fetching that has just happened.

**The pull is back, on the front page and nowhere else.** It was removed on the argument that the page keeps itself up to date and that a gesture always under the thumb invites being used. The page does keep itself up to date, and that argument was about the wrong thing : the gesture is not how the page keeps up, it is how a reader says *now* rather than *soon*. The clock is five minutes, politeness may defer beyond it, Low Power Mode and an expensive network both suppress the background pass deliberately, and iOS may grant no background slot for hours. It is also the gesture every reader already reaches for on the page they open first, and refusing it on principle asks them to learn a menu instead.

One place is enough, and the front page is where a reader is when they wonder. The wire has none : it is a list of what has arrived, and what arrives reaches it on its own. A Mac has no pull at all, and no command either since the command came out of the reader's menu : it keeps up through the clock, the full pass at rest, and the watcher that follows the store.

**The gesture is the fetching and the grouping, and it ends there.** Every feed, because they asked, and the grouping with it : pulling a page down means *show me what there is now*, and fetching without grouping would answer with the same stories and nothing else. The model's work carries on behind it, a headline written and a subject filed for every new story being one call apiece and seconds each, and a spinner held out for minutes is a refresh that looks stuck.

**The control lets go on the beat.** It used to spin until the gesture's work returned, and a whole family of faults came out of that one decision : the page was dragged down for the length of a fetch ; the space the control held was not always given back when it retracted, so the page stayed pushed down with the large title still open until anything at all touched the screen ; and content replaced just before returning had the scroll view begin its retraction against a page it had never laid out, which is why the pull alone could not read the page back. Four attempts at the second of those missed, and none of them could be reproduced on a simulator, where a synthesised drag never engages the control at all.

So the control is an acknowledgement and nothing more. It taps under the finger, says the pull was heard, and retracts on the beat ; what says the work is running is the ring in the reader's corner, where nothing it does can move the page. Nothing is held out, so nothing is pushed down, nothing has to be put back at its top afterwards, and the pull reads the page back as the last thing it does like every other pass. Three workarounds went with it : the scroll position binding, the flag watching how near the top the reader was, and the beat of sleep that kept the read-back from fighting the control on the way out.

## What Flong says it is doing

**A ring beside the reader's own button, while something is actually happening.** The page said nothing about any of it. A pass that fetched three hundred feeds, wrote sixty headlines and exchanged with iCloud was, to the reader, a page that changed under them for no stated reason, or worse, one that had not changed yet and gave no sign that it was about to. The only place that said anything was a footer buried in the sources list, which answers the question only for a reader who thought to go and ask it.

It names the stage rather than reporting a percentage of nothing in particular : fetching the feeds, grouping what arrived, writing the headlines, filing the subjects, indexing what was kept, synchronizing with iCloud, exchanging with the other devices, tidying up.

**It was a band across the head of the front page, and the page was the wrong place for it.** A line of words over a rule that filled, in the pinned header with the subjects. Everything it said was true, and it said it by opening a slot in the page every time a pass began and closing it again a few seconds later, on the one page the reader is reading. That happens several times an hour, mostly for passes nobody asked for, and a measure that moves the text under a reader's thumb costs more than it tells. Every refinement it needed says the same thing : the animated height, the fade timed to the height, the clip that had to be taken off again because glass casts a shadow. They were all repairs to the decision to put it in the page.

So the measure went where the chrome already is. It is round because the button beside it is round and a corner takes a ring where a line wants the width of a column ; it is small because what is happening is the machinery's business and not the reader's ; and it is in the toolbar, which is the one part of a scrolling page that does not move when something appears in it. It stands in the same corner of every section rather than on the front page alone, since a pass is the application's and not that page's.

**Inside a button that does nothing.** A disabled button, so it wears the shape and the glass of the reader's own beside it and is answerable by construction to no finger at all. The pull is the gesture ; something that reported progress and also took a press would be two commands in one place, and the reader could not tell which of them they had.

**One ring for the whole pass.** Every stage carried its own count at first, so one pass ran a bar from nothing to full five times over. A reader doing one thing and waiting for one answer does not read that as progress ; they read it as an application that keeps starting over. A pass declares what it is made of before it begins and each stage owns a share of the one ring, measured within that share by the queue it is working through.

**The shares are settled when the pass is planned and never move again.** They were recomputed from live counts as the pass went, so the arithmetic under the bar kept changing : a stage discovering it was bigger than it had been told made every earlier stage worth proportionally less, and the bar went backwards. A measure that retreats is a measure nobody believes.

**No stage may be worth nothing, and none may be worth everything.** A share is what the store says the stage will cost, blended halfway with an equal split. Weighted purely by cost, a pass whose stories had not been grouped yet gave the model's two stages nothing at all : the fetching owned the whole rail, and finishing it left the bar full with two stages still to run. Blended, no stage can reach the end before the end, and a fetch of three hundred feeds still counts for more than a briefing of three stories.

**No figures, and the words are said rather than set.** A count beside the measure is a second measure of the same thing, disagreeing with the first : the measure is the whole pass and a figure can only ever be the stage, so `9 sur 112` sat under a bar four fifths of the way along and the reader had to decide which of the two to believe. The ring says how far. What stage it is is said to VoiceOver as the ring's label and to a pointer resting on it, which is where a reader who wants to know goes looking, and it is a line the page no longer spends on a thing that is over in seconds.

**The item comes and goes, and the ones beside it do not move.** A toolbar keeps a place for what is in it, and a place kept permanently is a hole in the bar of every section for a measure that runs a few seconds an hour. So the item is there while there is something to say and not otherwise ; what it stands next to is the reader's own button, which is at the trailing edge, so nothing the ring does shifts anything the reader was aiming at.

**Where nothing in the pass can be counted, the ring turns instead.** An exchange with iCloud runs at the engine's own pace and a purge is a query : neither has a queue to measure, and a ring that sat at nothing would say the application had stopped. Under a third of the circle is inked and it goes round, which says *running* without claiming a position.

**Two floors keep it from flickering.** It appears only after a quarter of a second, because a catch-up that finds nothing due returns in a few milliseconds and a ring that appeared and left inside one frame is a flicker rather than information ; and once it has appeared it stays at least seven tenths of a second, because a measure that left before it could be read is the same fault the other way. Both live in the model, so the view stays a pure function of what is happening and no other screen has to reinvent them. The phase is read when the ring appears rather than when it was asked for, so a burst that passes through three of them inside that quarter second shows the one it has reached.

**A pass is named, and only its own name ends it.** The ring stayed up, and stayed up often. A pass was ended by whoever happened to call the end, and a pass is not always ended by the thing that began it : the steps inside a bigger one declare passes of their own, the enrichment closes the catch-up that started it from a task running behind the gesture, and the setup closed one from outside the call that opened it. Any of those arriving first closed a pass it had never opened, and left the real one with nothing to close it : the ring turned until the application was restarted. Beginning a pass now returns a name, an inner step is handed none and can therefore end nothing, and an end that arrives for a pass already over leaves the one running in its place alone. Every pass ends by a `defer`, so a way out added later cannot leak one either.

**And an exchange stops standing for work after a minute.** The ring has a second source : `CKSyncEngine` decides for itself when to send and when to fetch, and an exchange nobody asked for is still worth saying, so a status of `working` turns the ring on its own. An exchange opens on `willSendChanges` and closes on `didSendChanges`, and the second is not guaranteed to arrive : an engine interrupted, a process suspended between the two. Nothing ever ended it, so a status left at `working` was a ring that turned for the rest of the session. It is bounded now, generously enough for a real exchange of three thousand records on a slow network. What the bound ends is the claim on the reader's page, never what iCloud is doing : the engine carries on exactly as it was, and the status falls back on the moment it last actually finished rather than on a failure nobody can act on.

**The ring never runs backwards.** A resumable job works its total out afresh after every batch, as what it has done plus what is left, so articles arriving mid-pass raise it. Taken at face value the ring empties, which reads as the application undoing itself.

Under Reduce Motion the turning stops and the arc stands still, the same way `LiveDot` stops its pulse : a ring going round for ever is motion for its own sake, and the arc says as much standing still. The ring follows the type size, since it stands beside a control that does. VoiceOver reads the phase as the label and how far along as the value, and the element updates frequently so it is not announced batch by batch.

**The sources list keeps what a reader has to act on.** A full iCloud, a refusal, the offer to finish an import now : none of those belongs in a measure that disappears. Both places read the same phase, so they cannot come to describe one pass differently.

**Asking without the gesture is no longer possible.** `Actualiser` sat in the reader's own menu with its `⌘R` and was the only way on a Mac ; it is gone with the menu it was a line in. What is left is what the page does anyway : the clock while a window is open, the full pass at rest on the mains, and the watcher that follows the store. That is the position this document has argued from the start, and it is now the whole of it, with the consequence stated plainly : a Mac cannot be told to fetch by hand at all.

**The gesture is UIKit's control, not `refreshable`.** SwiftUI draws a pull-to-refresh for a `List` ; on a `ScrollView` the modifier is accepted and unreliable, and on this one, a lazy stack with a pinned header, a scroll position binding and an edge effect, no control was drawn at all. A reader pulling a page that does not flinch, while the same work ran perfectly from the command the menu then held, is one of the two paths never being called. `PullToRefresh` sits in the content, walks up to the scroll view it is inside, and hands it a `UIRefreshControl` : the control every application that needs this on a scroll view ends up reaching for.

It taps under the finger when it takes. The control emits nothing of its own, the system's own lists add theirs and SwiftUI's modifier added one, so a page that borrows the control borrows that too : a gesture that answers with a picture and nothing felt is a gesture the reader is not sure they made. The tap matters more now than it did, being most of what the gesture answers with before the control goes.

**And the ring answers on the beat.** It is held back a quarter of a second so that an automatic pass finding nothing due does not flicker a mark into the bar of a page nobody was watching. A pull is watched : the finger is still on the glass, and a beat of nothing between the gesture and the answer is what makes the answer look like it arrived from nowhere. What the reader asked for skips the wait ; everything automatic keeps it.

**And every pass ends the same way.** The pull was the one that could not read the page back as the last thing it did, since the control it was holding out would have retracted against content never laid out ; it was left to the watcher that follows the store, which reads back only when something happens to have been written. A gesture that asked for the page and got it only if something arrived is not the command it replaced by another name. With nothing held out there is nothing to except, and the read-back is the same call for the clock, the launch, the background and the pull alike.

## Pictures, and the marks beside them

**A hairline inside every picture's own edge.** A publisher's picture arrives at whatever contrast it was shot at, and one that ends in white sits on a white page with no edge at all : the line is what says where the picture stops.

**Inside, and not a ring around.** A ring outside is a mount, and a mount is a frame doing more than saying where the picture ends. Inside, the line is part of the picture's own edge and takes no room : nothing moves to make space for it. `strokeBorder` rather than `stroke`, since a stroke straddles the path and half of it would fall outside the clip, which is a line drawn at half its width and softer on one side than the other.

**A line, and not a material.** Glass was tried and taken out. At a point and a half it read as a band ; taken down to a hairline the regular material is a pale smear and the clear one is nothing whatever, measured at pure white against a white page. What is wanted is an edge, and an edge is a line. It is also hundreds fewer glass effects in a list somebody is scrolling, which are real resources and not free.

The separator's own colour rather than a white highlight. White is the glass idiom and it disappears on the picture that most needs an edge, which is the one ending in white on a white page ; the separator holds against both and turns with the appearance.

Half a point wide, at half the separator's opacity. A point was tried and read as too much : on a two times screen half a point is a single device pixel, which is exactly what an edge is. The separator's own colour is drawn to be read as a rule between two things and this is not that, it is the last pixel of the picture, so half of it says where the edge is without ever being the thing one looks at.

**A publisher's mark is round**, with the same hairline inside it. A favicon arrives as whatever square its publisher drew, dark on dark as often as not, and a round crop is what makes a column of them read as one column rather than as a row of unrelated stamps. The generic mark, for a source that serves none, keeps its bare glyph : an edge around it would make an absence look like a mark.

**The headline crosses the whole measure ; the picture comes in beside what follows it.** A headline is the widest thing a story says and the thing a reader scans for, and one squeezed into the column a thumbnail leaves over breaks across three lines where it would have taken two.

So a picture is not beside the story, it is beside the summary. The rubric and the headline run the full width above it, and what explains them shares the line with it. The row is a stack of three : the masthead, then the summary with the picture at its side, then the facts across the whole measure.

**The facts are under the picture and not beside it, because the moment has to land in one place.** The line ends in when the story was last added to, pushed to the far end of it. Beside a thumbnail that end is the thumbnail's edge ; on a story with no picture it is the measure, and on the lead it is the measure again. So the times marched down the page in two columns, alternating with whichever stories happened to carry a picture, and a column that moves is a column a reader stops reading. Across the measure there is one edge for every row.

An alignment guide was tried first, holding the whole text block to the left and pinning the picture to the summary's own top. It put the picture in the right place and left the headline in the wrong one, which was the fault being fixed.

**The pictures are decoded off the main thread, and were not.** The target builds with `SWIFT_APPROACHABLE_CONCURRENCY`, under which a `nonisolated async` function runs on its caller's actor rather than on the pool. Every caller of the image store is a view, so every caller is the main actor, so the ImageIO decode was happening on the main thread : one picture at a time, a few milliseconds each, for every row a reader scrolls past. A list that stops moving while it fills is the shape of that, and it is what the reader reported as the interface freezing.

`@concurrent` on the fetch is what takes it back to the pool. It never showed on a simulator, where a Mac decodes a photograph faster than a frame lasts ; it shows on a phone. The lesson is worth keeping rather than the fix : under approachable concurrency, `nonisolated` no longer means off the main actor, and anything expensive a view awaits has to say so.

## The article, over everything

**It was pushed and is presented.** An article went onto the stack of whichever section the reader was in, which drew it under the tab bar : a row of places to go, laid across the one thing in the application that asks to be read with nothing else in the way. It is presented from the window now, so the bar is behind it, and the page the reader came from is still there when they put it down.

It carries a navigation stack of its own, for the bar the controls hang off. That stack leads nowhere : what is on it is the article.

**It opens on the picture the row was carrying.** The article's own picture runs across the head of the page, above the headline, edge to edge and under the controls : the reader tapped a row with that photograph on it, and the page they land on opens on the same one.

**At its own height, and not cropped.** Every other picture in the application is shown at three by two, which is what makes a list of them read as a column ; a page is not a list, and it is the only place a photograph is looked at rather than glanced at. A portrait cropped to a landscape box on the one screen with room for it is a crop made for nothing. It also means the head takes no room until there is something to put in it : a box reserved at a ratio is a box that is empty while the picture loads, and stays empty if it never arrives.

The controls float over it. They are already on glass of the system's own, which is what keeps them legible over a photograph ; a band of paper behind them would be a shelf bolted across the picture.

**The byline is two lines, and every name on it is on a pill of its own.** Where it came from and when they ran it on the first, since both are facts about the piece as a whole and the date is the shortest thing a reader checks, so it sits where the eye already is. Who wrote it on the second, and nothing else on it. The author used to sit in a run of punctuation between the publication and the revision, which put a name between two timestamps and gave it the weight of one.

**One pill per person, never one pill per credit line.** Feeds have one field for this and publishers put whole newsrooms in it, separated by whichever punctuation the template happened to use : a comma, a semicolon, an ampersand, or the word for *and*. Two people are two people, and they are separated so that each is a thing on the page rather than a substring. `Dupont, Jean` is left alone, since that is one person written backwards and splitting it names two halves of somebody ; it is a guess, and it is the guess that fails quietly. No word in front of the names : a pill under the paper that ran it, holding a person's name, is a byline already.

**The dates lie on the page, under the people, and not on pills.** They were pills for a moment and it was too many pills : a pill is what the application uses to say *somebody*, this publisher, this writer, the source of this photograph, and a date is not somebody. Putting it in the same shape put a newspaper, two journalists and two timestamps on an equal footing, three lines of capsules before a word of the article. So the byline is who ran it, then who wrote it, then when, the last of the three in the muted grey the whole line was always in.

**A glyph says which date it is.** One clock for when it was published and the same clock turned back on itself for when it was changed : the pair has to read as *this time* and *that time again*, and two symbols from different families would be two things to learn instead of one. The word that used to say which is gone, since the glyph says it. A date and its glyph are held together, so a line may wrap between the two dates and never between a date and the glyph that says which.

**A rendered article is a web page, and a web page has no symbols.** Every other screen asks the system for one and is done ; here the symbol arrives as bytes, drawn once, black on nothing, and written into the stylesheet of every article. Black because it is used as a mask rather than as a picture : the page cuts the shape out of the text colour, so a glyph follows the appearance, the pill's own tint and Dynamic Type without anything knowing about any of them. A symbol the system does not know leaves its rule out, and the pill shows its words with nothing in front of them.

**What the glyph says is still said, to whoever is not looking at it.** A shape cut out of a background is nothing to VoiceOver, and two dates that read alike are two dates a reader cannot tell apart, so the word is in the pill and taken off the page. Text that is merely not visible, rather than an `aria-label` : a label on a bare `span` is at the mercy of what each assistive technology makes of an element with no role.

**A pill is a solid fill and a hairline, not glass.** Glass is worth its blur where there is something behind it to take : the credit over a photograph takes the photograph, and keeps it. In the article's own head there is paper behind and nothing else, so the blur was work done to arrive at a flat colour, and a flat colour is what a pill says now. The edge is the one the pictures on the front page wear, half of the separator : enough to say where the edge is, never enough to be the thing one looks at.

**A pill wears a wash of whatever its mark averages to.** The colour is the mean of the picture, worked out by drawing it into a single pixel, with the transparency divided back out : a favicon is a logo on nothing as often as not, and a pixel composited over a transparent ground comes back premultiplied, so a red logo covering a fifth of its square would otherwise average to a pale pink rather than to red. It is done once, where the pixels already are, and only for a picture small enough to be a mark : nothing wants the average colour of a photograph, and a list a reader scrolls through would be doing it for every one of them.

**The page cannot work it out, and must never wait for it.** Scripting is off in the reader, so the colour has to arrive already decided, in the rule. It is read from what the image store holds and never fetched : a pill that waited on the network to know what colour to be would be an article waiting on a favicon. The mark of the publisher whose article is being opened was almost certainly decoded a moment earlier by the row the reader pressed, and it is looked for at every address that mark might have come from, since a view stops at the first of the three candidates that answers and a page is handed only one. Where nothing is held, the pill wears the neutral grey and nothing is late. How much of the colour a pill takes is decided once in the stylesheet, more of it on a dark page than on paper, so a generated rule says only which colour.

**A person's pill has a place for their face, and nothing fills it yet.** A publisher draws a logo and every feed says where it is ; a journalist has a face and no feed format has a field for it, so a picture has to come from somewhere else : an `h-card` on the article's own page, a Micropub author, or the reader's own choosing. Whichever arrives, what it hands over is a picture per credited name, and the page already knows what to do with it. Each picture is numbered as it is met and set from the stylesheet rather than from an attribute, where the address would be escaped twice for no gain.

**Who published it is set apart from the rest of the line, on a pill, under the title.** Everything in the byline is the application talking about the article rather than the article talking, and one of the four is not like the other three : the author, the date and the revision describe this piece, and the publisher is the one fact that is the same for every piece they have ever run. It is also the only one looked up rather than read off the article, so a reader who renames a publisher renames it here too, and the mark they know it by stands in front of the name, since a mark is recognized before a name is read. It is the same pill the picture credits wear, so a reader meets one shape for *this came from them* rather than one per screen.

**The page gets one address for the mark and no second try.** A view asks for the three candidates in turn and stops at the first that answers ; the article is rendered with scripting off, so nothing in it can notice that a picture failed and reach for the next, and a stylesheet naming three addresses paints all three on top of one another rather than falling through them. So the order changes where there is one go at it : what a feed states is still first, and failing that it is `favicon.ico` rather than `apple-touch-icon.png`, the touch icon being the better picture and the more often absent. Where there is no mark the box for it is dropped rather than kept empty, since a box kept for one that never arrives is a hole in front of the name for the whole life of the page.

**One side owns the inset at the top, and only one may.** A scroll view that adjusts itself for the safe area gives itself a top inset : a region above the document that can be scrolled into and stays there, which is not a rubber band that springs back but real empty space above the page, white under the controls. That is right when the page begins below the bar. It is exactly wrong when the page runs under it, where the view has already been extended to the top of the screen and the inset is counted a second time. The web view adjusts itself only in the first case.

**The bar is settled before the article arrives, not after.** What it looks like and what it lets the page run under were declared inside the branch that draws the article, which is the branch that appears once the article has been read out of the store. A navigation bar told what to look like after it has already laid itself out keeps the look it had : a band of paper across the top with the page beginning underneath it, which is what a device slow enough to draw a frame without the article showed and a simulator fast enough never did. They are declared outside that branch now, so they are what the bar is from the first frame. **The bar carries no title**, and cannot : plain type over somebody's photograph is unreadable on half the photographs there are. The publisher is named in the byline under the headline, where the page says it in its own voice.

An article with no picture starts where it always did, below the bar. There is nothing to run under it.

**The picture is taken out of the body.** An article's picture comes from the feed or, failing that, from the first picture in its body ; in the second case the head and the first paragraph would be the same photograph twice, one above the other. What is removed is the tag and nothing around it, so a caption stays with whatever is left of the figure it was in.

**The way out is a cross, not a way back.** The reader is not returning to a screen they left. The page they came from never went anywhere, and an arrow pointing at something already behind the article would be describing a journey nobody made. A cross says what this is, which is a thing put down.

`Route.article` stays a route, since an article is a place a reader can be ; it is simply not a place on a stack. One function in the window decides which of the two a route is, so no screen has to know what its own rows do.

## The panels, in the leading corner

**Short sheets from the bottom, and no longer pages.** The sources, the subjects and the notices were a screen apiece, two of them behind a line in the reader's menu, which is two presses and a way back for what a reader does in a moment. None of them is a place to be : one answers a question about being interrupted, one nudges a subject and watches the page take it, one picks a feed and reads it. In all three the page they were reading is still behind the panel, and a panel goes with a flick.

Three buttons stand in the leading corner, in the order a reader meets what they hold : the sources they follow, the subjects the page is sorted into, the notices they may be interrupted by. The subject wears `circle.grid.2x2` wherever it appears, which is a grid of sections rather than the stack of cards it used to be.

**The three in the leading corner are titled ; the reader's is not.** A title was taken off all four and put back on the three, which is the right answer for a different reason on each side. The three are places the reader went to on purpose, and a panel over a page of headlines wants a word saying which of the three arrived. The reader's opens on their own face at ninety-six points : nothing a title could say about who that is about would say it better.

**The way out is a flick, and the indicator says so.** There is no `Terminé` : a button that repeats what the gesture already offers is a control spent on nothing, and the indicator at the head of every panel is the thing that says a panel is a panel. A Mac keeps the button, and only a Mac, since a Mac sheet cannot be flicked and would strand the reader with no way out at all.

**The sources and the subjects stand taller and scroll.** One switch has a height of its own ; a list of publishers, or fifty sections and however many the reader wrote, wants the height a reader chooses. Both open at a height of their own rather than at `.medium`, which is measured off the bottom of the screen and takes the panel's lower corners with it, and both pull up to the whole screen.

**Picking a source closes the panel.** It is the one of the three that leads somewhere : the panel goes and the page it asked for arrives behind it, rather than staying on the stack as a way back nobody asked for.

**A panel is not a page, and is not pulled.** `refreshable` puts its action in the environment, and a sheet inherits the environment of whatever presented it : declared under the front page's toolbar, the pull reached the panels the buttons up there open, and a list of subjects offered to fetch three hundred feeds. It is applied to the page it belongs to and above the toolbar, which is where its scope should have ended all along.

**It floats, and the system draws that.** A sheet here is already inset from the edges of the screen and rounded on all four corners. What squared it off was what was put inside it : a `List` paints its own background edge to edge, over the rounded corners and down past the safe area, so the panel read as the page having been cut off rather than as something laid over it. A panel of one's own drawn inside the sheet is no better, being a second surface inside the one the system already drew. Nothing in it paints a background of its own now, and the shape the system draws is the shape that shows.

Its height is fixed rather than half the screen : a sheet at `.medium` for one switch is a great deal of nothing under it. It is the height of the sheet and not of the panel, the system insetting the one inside the other. The one thing that makes it taller is a refusal, which adds a line saying why nothing there can be turned on and the way to the system settings.

**It says nothing it does not have to.** It carried a heading, `Ce que Flong vous signale`, over a single switch : a heading over one thing names the list it is heading, and a list of one does not need naming. Under the switch was a paragraph explaining what a story is, to a reader who reaches this panel from a page made of them. What is left is the switch and its own name, which is what they came to set.

## The reader's panel

One button in the same corner of every section, holding what belongs to the reader. It sat in the digest alone at first, which made it the digest's menu rather than the reader's : what it holds belongs to the person and not to the page, and a thing that belongs to the person is in the same place wherever they are.

It is still not an account. There is no account and nothing to sign in to, and the face on the button is the reader's own picture rather than a sign that they are signed in to something. It is called `Réglages` in French.

**It was a menu and is a panel**, the fourth of them, built like the three in the other corner : untitled, closed by a flick, over the page rather than in front of it. A menu of lines leading to screens was the wrong shape for what was behind them, a name and a face and the sites the reader pays for being things they set and come straight back from.

It holds the reader's face and name, how the application is set, the sites they are signed in to, and, in a build being worked on, the command that makes the exchange with iCloud happen on demand.

**The theme is chosen here because a theme is about the reader.** Which face they want to read in is not a fact about any feed they follow : it follows them to their next device, like their name and like the body an article opens on, and it belongs under their own face for the same reason those do. `Actualiser` is gone with the menu ; the page keeps itself up to date, which is what this document has said all along.

**The notices and the subjects came out of it.** Not because they are opened often, which they are not, but because of the shape of what a reader does in them : they say one thing about the page they are looking at and go back to reading it. Two presses to reach a whole screen with a way back on it is the wrong shape for that, however rarely it is done. Both stand beside the sources in the leading corner now, and all three open panels over the page.

It holds `Forcer la synchronisation`, under `#if DEBUG` and nowhere else. The engine decides when to send and when to fetch and is right far more often than a button would be ; what that command is for is watching an exchange happen on demand while something is being built. It queues every record this device holds, which is the repair path and costs a few thousand records against a budget of three thousand, and that is why it does not ship.

The command to write the digest again was here and is gone, replaced by that one. Nothing in the interface asks the model to re-read a page it has already read : stories already filed are never re-read, which is what makes the page stable.

**The section is called `Collections`, not `Bibliothèque`.** A library is a shelf of books, and what this section holds is articles somebody put aside ; `Bibliothèque` was also the longest of the four names in a bar that has to fit four. `Collections` is what Photos calls the same idea for the same reason, which means a reader has met it before. The word outlived the thing : the library it was renamed from is gone from the store as well as from the bar, and `docs/technical/marks.md` says why.

**The bar's three marks are one family, and they had to be made one.** A tab bar fills its symbols itself, so every mark in the row arrives as its `.fill` variant : solid shapes with weight. `dot.radiowaves.left.and.right` has no filled variant, so it stayed a hairline drawing between solid ones, which is what unbalanced the row. The stream takes `tray.full` instead, which fills, and which is the mark the same view already wears in the sources list, since it is the same view. What is left is the front page's newspaper, a full tray of what has come in, and a folder of what the reader filed, all three drawn at the same weight. The digest wore `sparkles.rectangle.stack` first, which said a machine had been at work on it ; what the tab names is a front page, and a reader who has seen a newspaper knows what one is without being told that a model helped make it.

**The sources came off the tab bar, which is now four sections and not five.** A tab names a place there is to read, and a list of sources is not one : it is something a reader touches when they are organizing, which is rarely, and the bar is better spent on reading.

They are not in the menu either, though they passed through it. They were the one thing in it a reader opens often, and a thing opened often is a button rather than a line in a menu : they sit in the leading corner, opposite the reader's own face, in each of the three sections a reader reads in. Search does not carry it, its bar belonging to the field, and a reader who is searching is not organizing.

The one thing that move could have broken is the first launch, where a reader who follows nothing had the sources tab in front of them and now does not. The front page says so instead : with no feed at all it offers adding one and importing an OPML file where the reader is already looking, rather than explaining what grouping is to somebody with nothing to group.

**The subjects screen is the other half of the pills.** A pill carries a subject of the day, where an opinion is formed and where saying it costs one press. The screen carries every subject there is, including those that have fallen off the page, so a reader who asked for less of something months ago can find it again and take it back : a preference nobody can find is a preference nobody can undo. Each row is a picker of three, down, nothing, up, rather than the pill's nudge by one : here the reader is choosing a side, and reading back three shades of the same side would be a control that says more than it lets them say.

**The face is the button.** A name and a picture, both optional, both the reader's own, kept in their own iCloud beside their other preferences. There is nowhere to send them : section 3 says there is no server, and a name typed into a feed reader is not an exception to that. What they buy is that a device the reader picks up looks like theirs, and that is the whole of it. The mark has three states, in the order a reader arrives at them : the picture they chose, the initials of the name they typed, and the generic face of somebody who has told the application nothing. The third is not a failure and is not nagged at.

The picture is scaled on the way in and never after. What comes out of a photo library is a photograph, twelve megapixels and four megabytes ; what is wanted is a mark twenty-six points across. It is resized once to two hundred and fifty-six pixels, re-encoded as JPEG so that a HEIC from a phone and a PNG from a Mac take the same room, and anything that still exceeds a hundred and twenty-eight kilobytes is refused rather than allowed to fill a store that holds one megabyte for everything. A face on a phone comes from the photo library, through the picker Apple runs outside the application, so nothing here ever sees the photo library and no permission is asked for ; a face on a Mac comes from the open panel, because a Mac reader offered a photo library would be offered the wrong drawer.

**Where the reader is sits under their name, and is one row rather than two fields.** A town typed by hand is a spelling, and two readers who both live in Lyon would spell it two ways ; what the picker gives back is a place MapKit recognizes, with the country code that goes with it, which is the half a later feature will actually match on. The row shows what was chosen and opens the picker, and taking it back is a line of its own, so it is never done by pressing the same row twice. The picker offers the device's own answer first and a search under it, and the search is the one that matters : it needs no permission, it works on a Mac with no receiver in it, and it is where a refusal leaves the reader standing. What is kept is a name and never a coordinate, for the same reason the picture is scaled on the way in : what is wanted is the small true thing rather than everything the system could hand over. `docs/technical/place.md` records the two paths and what is sent to Apple while the reader is choosing.

**It is called `Votre édition` in French.** The English row names what it holds, a city and a country, since that is what the reader is being asked for ; the French names what it is for, which is the edition they are served. `Réglages` over an untitled panel is the same licence taken for the same reason : two languages are not obliged to arrive at a name by the same road, and a French row reading `Ville et pays` named the fields rather than the point of them.

**It says its own failures.** The shell's alert is two sheets below by the time the picker is open, and an alert presented from under a sheet is one nobody sees. So the picker carries its own, and there are three sentences and not one, because there are three different things for the reader to do : go to the system settings, type the name of their town, or pick a different one.

**The danger zone is at the foot of it, and nowhere else.** Deleting everything is the one command in the application that takes something away for good, and it belongs under the reader's own face for the same reason the name and the picture do : everything else in this panel is what they chose about themselves, and this is them taking all of it back. It stands last, and it does not look like the settings above it : a card of red glass carrying its own heading, the sentence that says what will go, and one prominent red button, out of the grouped background the rest of the panel sits in. That is deliberate and is the material's one exception, recorded above : a setting is a thing a reader changes their mind about freely, and a row that looks like its neighbours is a row that is pressed like its neighbours. It asks before it acts, with a sentence that names what goes rather than warning in the abstract. The panel closes when the work is done, so the reader lands on an application that looks like a first launch rather than on a settings page reporting a success. It is honest about the one thing it cannot do : another device that still holds the subscriptions will recreate the zone and put its copy back, and the alert says so rather than promising a reach a design with no server in it does not have. `docs/technical/erasure.md` records what it reaches and in which order.

**Marking everything as read left the sections a reader lands in.** It is a command about a list, and the two sections that had it are not lists of a thing to get to the end of : the stream is a wire and the collections are what was put aside. It stays where it means something, on a feed, a publisher or the unread view, each of which is a list with an end. What takes its place in the corner is the reader's own menu, which is now the same one button in all four sections.

**A story is a `fil` in French, and a subject is a `thématique`.** Both English words translate naturally to `sujet`, and only one of them could have it. The first attempt gave it to the story and left the subject as `thème` ; that reads backwards, since `sujet` in ordinary French is exactly what a subject is, and it cost a round of the two being confused for each other in conversation before the naming was settled.

`Fil` says what a story is, several articles following one thing, and `thématique` is unambiguous where `thème` was merely unclaimed. The cost is that the stream section is called `Flux`, so `Fil` and `Flux` sit near each other ; they are different words for different things and the sections they name are never side by side.

## The day over the wire

**The glass arrives with the scroll, and the month narrows into it.** At rest the chart runs the whole width of the screen and wears no material at all : glass over nothing is glass doing nothing, a material's whole job being to say that something passes behind it. The first row to go under the bars brings it, and the month steps back into the column the rest of the page is set in as it comes. The two are one movement, driven by the reader's own scroll, and both go again when the page returns to the top.

A month is a picture of a whole month and reads better for having the whole width ; a piece of glass is a thing on the page and belongs within the measure like everything else on it. Uncovered, the chart steps out of the page's gutter with a negative inset of exactly its width, which is why that gutter is a named constant rather than a number written twice.

The offset is what is asked, not the rows : a row is a landmark and this is a question about a single point, the top of the content against the top of what is shown. Against a hair rather than against nought, since a scroll view rests at a fractional offset often enough and a glass flickering on and off under a still thumb would be worse than one that never left.

**The bars carry the page's own ink, softened by a hair.** A bar wants the weight of the ink or it stops being something to count by ; what it does not want is to be the hardest edge on the page. So the colour is the ink and the softening is a transparency on the bar itself, which also lets the glass under the strip, and whatever headline is passing beneath that, show through very slightly. Measured against a white page : the full ink at nought, held back to half a mid grey too faint to read a day by, held back a tenth a shade off black, and this at thirteen.

**The hour turning over is felt as well as seen.** The buzz followed the day while the chart counted days ; it follows the hour now that the mark does, since a reader scrolling through a whole day of a busy wire without feeling anything is the chart moving under them in silence.

**An hour with nothing in it is grey, not absent.** Whether it has been and gone or has not happened yet, it keeps its place at the height of the shortest bar there is. The row stays a row, with a level floor an eye can run along, and the ink is kept for the hours something actually arrived in.

**It counts hours over a day, and not days over a month.** A month of thirty-odd bars says which weeks were busy, which is a fact about the press rather than about the reading : somebody looking at a wire wants to know what has come in since they last looked, and that is a question about this morning and last night. Exactly the hours the day has, which is twenty-three, twenty-four or twenty-five, since the day the clocks go back is twenty-five hours long and a chart that always drew twenty-four would put an hour's arrivals somewhere they did not happen.

**It is followed, never dragged.** The day it shows is the day the reader is in and the coloured bar is the hour they have reached, both read off the list as they scroll it. A second scroll of its own, on the same screen and at right angles to the first, would be two ways of moving through one page and a way of putting the two out of step ; the strip moves by being followed.

## Two kinds of moment, and only one of them counts back from now

**A story's moment is relative and an article's is absolute**, which is not an inconsistency but the difference between the two things. What a front page says about a story is how fresh it is : `il y a 3 minutes` is exactly that, and it is the reason the line is there. An article is a thing with a date, and the date is what a reader wants of it.

Article rows read `il y a 2 heures` before, and a list of one morning's articles came out as twenty phrasings of the same hour, none of them comparable at a glance and all of them going stale while the page sat open. Two articles an hour apart are `9:05` and `10:12`, and the reader does the subtraction they were going to do anyway. The day and the month come with it, and the year only where it is not this one : a stamp reading `11:15` is unreadable in a list reaching back three days, and one carrying `2026` on every line of today's news is a column of noise.

**A story's moment is a glyph and no words.** It read `mis à jour il y a 21 minutes`, which is a sentence in a row of shorthand : the rooms are marks rather than names and the arrivals are a sparkline rather than a count, and the line has no room to be the one part that explains itself. The mark is `clock.arrow.circlepath`, which is what a rendered article already wears for a revision, so a reader who has opened one article has met it. What the words said is said to VoiceOver, which has nothing to look at.

## The dateline

**The title of the page is the date.** Not the name of the section : the tab bar says that already, and a page that repeats its own label has spent a line saying nothing. A dateline says what the label did not, which is how old what follows is allowed to be, and it is where a newspaper puts it.

It is a large title like every other section's, so it shrinks into the bar as the reader scrolls into the page. It is spelled the way the reader's language spells it, with only its first letter raised : French writes `samedi 29 août`, and capitalizing every word would give `Samedi 29 Août`. It is read at each render rather than held, so a page left open overnight is not still yesterday's.

There is no refresh button. The page refreshes itself on returning to the foreground, on the store changing, and on the five-minute clock ; a pull says now rather than soon on a phone, and a Mac has neither, which is the position this page has argued from the start.

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

**The mark stands in front of the line it is about.** It was a pair of sparkles among the facts, at the far end of the row that counts the rooms and says how long ago the last article came : a screen's width from the sentence it referred to, in the company of everything the store knows for certain. A reader who wanted to know who wrote the words they were reading had to look elsewhere and then work out that it pointed back. `StorySummary` draws it where it belongs, in front of the sentence, on both the front page and a story's own page, so it is read in the half second before the sentence is, which is the only time it matters.

**And it is `text.line.3.summary`, not `sparkles` and not `apple.intelligence`.** What the mark is about is a summary, and a glyph of a summary says so ; sparkles say that something clever happened, which is a claim about the machine rather than about the line. The Apple Intelligence symbol says which model, which is more than either, and it was tried : it is a restricted one, sitting in `symbol_restrictions.strings` beside `apple.logo`, `siri` and `safari`, the set Apple reserves for depictions of its own products and features. It renders perfectly in a third-party application, so the objection is a licensing one rather than a technical one, and it is not worth carrying to a submission for the sake of a glyph. `text.line.3.summary` carries no such restriction.

**Set into the line, and not stood beside it.** It was given a column of its own first, with the sentence indented past it, and that is a label pinned next to a paragraph : it holds a gutter open down the whole page, it takes width from the words at the one size where they have least to spare, and a summary of three lines reads as a quotation. Inline, the glyph is the first thing in the sentence and the wrapped lines come back to the margin under it, which is how Mail sets the same mark on the same kind of line and therefore the treatment the reader has already met. It is set a size under the words, at about four fifths of them : a symbol is not a letter, it fills the cap height of whatever font it is given and comes out heavier than anything beside it, so a mark at the size of the sentence is the loudest thing in the sentence. A step of the scale rather than a size in points, so it still grows with the reader's type. It costs a single run of text : two views cannot break as one sentence, so the line is built by concatenating `Text`, the way the tick at the end of a read headline already is. That operator is deprecated and its replacement cannot be used here, since interpolating into a `Text` means interpolating into a localized key, and a summary written by a model on this device is translated by nobody : the catalogue would gain `%@ %@`. **And the mark says it alone, in no words at all.** A story's page carried a row under the summary reading `written by the model`, which is the application talking about itself over the top of the news : a caption on every written line, saying in words what the mark in front of that line already says. The words are gone and the line itself is the control : a reader asking who wrote this presses this, which is where they were already looking, and the same popover comes up with the same way back to the article's own headline. What is said in words is said to VoiceOver, which reads nothing where the eye reads a mark : that is the mark read out and not a caption restored.

## What the model wrote, and how to refuse it

A story's name and its one line are written on the device by the system model. The row says so, with a mark, and the story page explains in one sentence what was done and offers to fall back on the article's own headline. Section 14 of the specification requires the first ; the second is what makes the first honest, since a label the reader cannot act on is decoration.

Where there is no model, or where it refuses, the story is named after its most central article. The page is entire either way.

## What 2026 asked for, and what was ignored

The year's design writing converges on cognitive clarity over sensory richness : calm surfaces, fewer simultaneous signals, motion used as information, artificial intelligence made visible, optional and explainable rather than ambient. That is the page above, and it is also why the digest states its evidence out loud : four rooms, five articles, this shape of arrival, seventeen minutes ago. A story that cannot say why it is on the page does not deserve to be.

What the same writing recommends and Flong does not do : ambient gradients behind content, a bento grid of unequal cards, an assistant panel, and depth for its own sake. They are all ways of adding sensory richness to a screen whose whole job is to be read.

## Accessibility

Dynamic Type carries the layout : the measure is a maximum, not a fixed width, and every row grows. Icon-only controls carry a label. The facts line is combined into one accessibility element per story rather than read as six fragments. The live dot never conveys its meaning by motion or colour alone, since the section header next to it says the same thing in words.
