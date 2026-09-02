# Notifications

Everything Flong may interrupt the reader for, and the rules it interrupts them under.

## Local, and only local

There is no server, so there is nobody to send a notification. Every one of these is written by the device that shows it, about something that device worked out for itself : it read its own page, found its own subject, and told its own reader. A second device may say the same thing at a different moment, or never, and that is correct rather than a drift to fix.

The `aps-environment` entitlement is there for `CKSyncEngine`, which uses a silent push to say that another device changed something. Nothing that arrives that way is ever shown to the reader.

## Where the switches are

A panel from the bottom, opened by the bell beside the sources, in the leading corner of every section a reader reads in. It was a line in the reader's menu leading to a screen of its own, and one switch does not want two presses and a way back : a reader who turns a notice on is answering a question and going back to what they were reading, which is still behind the panel while they answer.

There is no master switch. A list of two switches with a third above them that overrules both is a list where nobody is sure what is on, and the system already has that switch, in the place a reader looks for it.

The panel is not the only place a notice is asked for. A source announcing its own articles is switched on where the source is, since it is a decision about that publisher ; the panel lists the ones that are on, so that everything Flong may interrupt the reader for can still be seen, and quietened, in one place.

## Permission is asked when the reader asks

Every switch starts off, and turning one on is what asks the system. A prompt at first launch is a prompt about something the reader has not seen yet, which is how an application gets refused permanently for a feature that would have been welcome later.

A refusal is final until the reader goes to the system settings : asking again does not prompt, it returns the refusal. So the switch goes back where it was and the screen says where the answer lives, which is the only honest thing an application can do about a refusal.

**What the reader wants is carried between devices ; whether a device may interrupt them is not.** The preference is a decision about themselves and travels through the iCloud key-value store like every other one ; the permission is the system's answer on one device and never travels. It is right that the two disagree : a reader may want the notices and have refused them on the Mac.

## New stories

The first of the four.

A story is several articles, from several newsrooms, about one thing : the unit of the front page, and the whole difference between watching a field and watching a list of what arrived. A story opening is the moment the press starts covering something, which is the one thing in a feed reader worth interrupting somebody for.

**A cluster of one is not a story**, so this is not a notice per article. Two articles have to be close enough in vocabulary to be about the same thing before anything is opened at all.

**What counts as new** is a story row opened since this device last said anything, **and that the front page will actually show**. The identifier answers the first half : every technical key is a UUIDv7 and carries the moment it was made, so the question is a range on the primary key rather than a scan. Nothing else records it, `first_at` being the date of the story's earliest article, which may be days older than the story.

The second half was missing, and the two questions came apart. The page holds a story to the three-day window and to having more than one article left inside it ; the announcement asked the key and nothing else. A pass that grouped a quiet feed's week-old backlog into stories announced every one of them and put none of them on the page, so the reader was told about news they then could not find : a notification about a page that had, as far as they could see, not changed at all. The announcement asks the same three questions the page asks.

Everything that was already open when the reader turned the notices on is not new : the watermark is stamped at that moment rather than at the beginning of time.

**The watermark is this device's own**, kept in `UserDefaults` and never carried. One that travelled would have the second device stay silent about what only the first had announced.

**Nothing interrupts a reader who is looking at the page it would be about.** A story that opens appears on the front page, so a reader with Flong open has already seen it, and a notice about something they watched happen is a notice to dismiss for nothing. The watermark moves anyway : what it records is that the story reached them, not that a notification was posted. Being told tomorrow about what they saw today would be worse than not being told.

**One story leads with its own headline.** The headline is the news, and a notification titled `New story` with the headline underneath buries the thing the reader is being told. Underneath goes the line the model wrote saying what happened, or, when there is none, the newsrooms covering it, which is the front page's own signal that something is happening. A tap opens that story.

**Several are counted in the title and listed in the body**, so the two always agree, and the headlines are joined by a middle dot rather than by commas : a headline may hold commas of its own, and a comma list of them reads as one long broken sentence. A tap opens nothing, several stories not being a place to go.

Announced after the model has written the headlines rather than before, so what the reader is shown is the written headline and not the title of whichever article happened to be nearest the middle of the group.

## Every article of one source

The question the stories cannot answer. A story is several newsrooms covering one thing, which is the right unit for the press and the wrong one for a reader who follows one newsletter, one blog or one colleague : a piece nobody else covers never becomes a story, so it would never be announced, and it is exactly the piece that reader is waiting for.

**Asked of a source or of a writer**, which are two switches and one notice : see the section below for why an article that answers both is announced once.

**The switch is on the source and not in the panel.** It is a decision about a publisher, like the favourite beside it, so it lives on the feed's own row and travels in the feed's own record : a reader who asked to be told about one paper on their phone did not mean only on their phone. A list of identifiers in the key-value store would be a second place naming sources, going stale the moment one is unsubscribed from and needing a rule of its own for what happens when one moves.

**It is not the favourite under another name.** A favourite source is one the reader wants near the top of their own lists ; this is one they want to be interrupted for, which is a great deal more to ask. A reader with forty favourites who found they had signed up for forty notifications a day would turn the lot off, and the two are deliberately separate switches, in separate lines of the same menu and separate sections of the same editor.

**There is still no master switch**, which is why nothing was added to the panel to overrule these. What the panel gained is a list of the sources that are on, so that a reader who has asked about six of them can see all six in one place and quieten any of them there ; adding one is done where the source is.

**Reached three ways, and asked for once.** The source's own editor holds it in a section of its own, the long press on a source in the sources panel toggles it, and the notifications panel takes it back off. All three go through the same call, which asks the system before writing anything : a source saved as announcing on a device that has refused Flong every notification would be a switch that promises what it cannot deliver.

**What counts as new is what arrived here, not what is dated today.** A source that backfills a month of articles published them a month ago and served them tonight, and a notice about what carries today's date would be silent about everything the reader actually just received. The watermark is compared against `received_at`.

**What is read, hidden or a second copy is left out.** A rule the reader wrote to never see something is not undone by a notification ; the same article arriving through two feeds of one newsroom is one piece of news ; and being told about what they read on the iPad an hour ago is worse than not being told.

**The question is asked of the feeds and not of the articles.** A reader asks about a handful of sources out of hundreds, and a partial index covers exactly those, so a pass that brought nothing from any of them costs one look at almost nothing.

**One article leads with its own headline**, for the same reason a lone story does, with the source underneath, and a tap opens the article over whatever the reader was on. **Several from one source are counted under its name**, since the source is what the reader asked about and naming it once is shorter than repeating it. **Several sources are counted and then listed by name**, the headlines giving way : a reader told `5 new articles` and left to work out where from would have to open the application to learn what they were just told.

**Announced where the articles land, and not where the model runs.** The stories are announced after the headlines are written, since the written headline is what the notice says ; this needs nothing written and nothing grouped, so it is said at the end of every pass that fetched, the twenty-five seconds of a background refresh included. Those are the moments the reader is not looking, and they are what this exists for.

**A decision arriving from another device says nothing about the backlog.** The switch travels ; the watermark does not. A device that has never said anything and meets a source already switched on stamps its watermark and stays silent for that pass, so the next one is the first that can speak.

## Every article of one writer

The same request, asked of a person. A reader who follows somebody follows them wherever they write, which is the whole point of asking of the writer rather than of the paper : the article turns up whichever feed carried it, and a person who moves papers is not a subscription to redo.

**A table of its own, and not a flag on the favourites.** A favourite writer is somebody the reader wants gathered on a page ; this is somebody worth being interrupted for, and they are different judgements exactly as they are for a source. A column on `favourite_author` would have meant making somebody a favourite in order to hear from them, and a row there whose flags both said no would be a favourite that is not one : the presence of that row is the whole of what it says. So `notified_author` mirrors it, one row per writer asked about, and its deletion is the `no`.

**Named after the writer, like everything else about them.** There is no row per person and there could not be one : what a feed hands over is a byline, so the name is the identity and it is matched exactly. `docs/technical/authors.md` sets out why.

**And the same again, asked of somebody an article is about.** `notified_newsmaker` is the writers' table with the question changed : a reader following a person hears whenever any paper writes about them, whoever signed it. It is named after the person for the same reason and matched exactly for the same reason, and it carries a record prefix of its own so that following a writer and following somebody of the same name stay two decisions.

**The people are read out of what a pass brought before that pass announces anything.** The watermark moves whether a notice was posted or not, so somebody found a moment after the announcement would be a notice the reader never gets, for ever. `docs/technical/newsmakers.md` sets out what that costs and how it is bounded.

**A byline naming several people answers for the one asked about.** The row per person that sits beside each article is what makes that possible : a piece signed `Claire Ancelin et Paul Rey` where the reader asked about Paul Rey is news about Paul Rey, and the notice names him rather than reading out the byline.

### One notice per article, however many ways it was asked for

The thing that would be wrong twice over. A writer somebody follows very often writes for a paper they follow as well, so an article can answer both requests at once ; asked as two questions it lands in both answers, and the reader gets one notice about the paper and a second, moments later, about the person.

**So it is one question.** `ArticleStore.arrived(since:)` asks for what arrived from an announcing source *or* signed by a writer asked about, in one statement, and an article is one row in the answer whichever of the two brought it. The guarantee is by construction rather than by filtering afterwards, which is what keeps it true for a case nobody thought of.

**The person leads the wording** where both apply, since asking about somebody is the more particular of the two requests. Under a single headline goes the person and the paper, joined the way the application's own bylines are : it is the answer to *why am I being told this*. Several are counted under whatever was asked about, the person where there was one and the source otherwise ; several of those are counted and then listed by name.

### Where the switch is

On the person's own page, in the toolbar beside the star, and in the long press on a row of the authors directory. The bell is never merged with the star : one control doing both would have every reader who liked forty bylines signed up for forty notifications a day.

The notifications panel lists the writers beside the sources, in one list and not two. They are two kinds of thing to the machinery and one thing to the reader, who is looking at what may interrupt them ; the glyph says which is which, a publisher wearing the aerial the sources list gives it and a person a signature.

## Somebody added to a shared collection

**The one notice here that is a person and not a calculation.** Everything else Flong may say is something it worked out on its own, from feeds nobody else touched. This is somebody doing something, which is why the person leads the sentence and the collection follows it : a notice reading `2 new articles`, leaving the reader to work out who and where, would be the least useful way to say the most interesting thing in the application.

**The people are counted and not the filings.** One person adding four pieces is one thing happening ; four names would be four things. Where several people filed into one collection, the collection is named in the title and the people are listed underneath. Where they filed into several, the title says so rather than naming one of them and being wrong about the rest.

**A switch that only appears when there is something for it to be about.** A device in no shared collection is a device whose reader has never seen one, and a question about something they have never seen is a question they cannot answer. The switch arrives in the panel the moment they share a collection or accept an invitation to one.

**And a switch per collection, which is the point of it.** A reader in four shared collections is usually loud about one. The quiet ones are stored as a list of the quiet ones and never of the loud ones : storing the opposite would have every collection they were newly invited to arrive silent and look broken. It is by zone, since two people may perfectly well call a collection the same thing, and it travels with the reader like every other thing they want. The per-collection switch is only offered where the notices are on at all, since one that quietened a collection nothing was ever said about would read as broken the first time it was used.

**Nothing is said about what the reader filed themselves**, and the muted collections are left out of the query rather than filtered after it, so that a muted collection cannot move the watermark past one that is not.

**When a thing arrived is not changed by somebody editing their list.** A participant's list is rewritten whole every time any of it changes, so the moment a row turned up here has to survive that rewrite : without it, an article that had been here a week would be stamped as new the moment its filer added something else, and announced all over again. `SharedEntryStore.replace` reads the existing arrival times and keeps them.

## Where it happens

The digest is rebuilt wherever articles arrive : at launch, on the clock, on returning to the foreground, on the reader's own command, in the opportunistic background refresh and in the full pass. Only the background ones are moments the reader is not looking, and they are what this exists for.

**Both background tasks were dead when this was written.** They were registered while the application launched, as they have to be, against a box that nothing ever filled ; on iOS no request was ever submitted either, so the system had nothing to schedule. Both are fixed here, since a notice that can only fire while the reader is watching is a notice that never fires.

## Tapping one from a cold start

The delegate has to be in place before launching finishes, or a notification tapped from a cold start is never handed over. The window and its model do not exist that early, so `NotificationRouter` is set as the delegate in the application's own initializer and holds the answer until the window claims it, exactly as `BackgroundWorkBox` does for the background tasks.

## What is testable, and what is not

The delivery needs an authorization, a bundle and a device, none of which a test can rely on, and none of which is where the mistakes are. `Announcing` is the seam : `Notifier` is the system, `MemoryAnnouncer` is a list a test reads back.

What that buys is coverage of everything that can actually be wrong : the wording and the plural, the headline leading rather than being buried, the written line taking the place of the newsrooms when there is one, the middle dot rather than commas, which stories count as new, that nothing is said twice, that nothing is said while the reader is reading and that it is not saved up for later either, that a refusal leaves the switch where it was, and that a reader who asked for nothing has their watermark left alone so that turning the notices on later starts from that moment.

For a writer it buys the guarantee that matters most : that an article from a source that announces, signed by a writer who is asked about, is announced once and not twice, which is a property of the query rather than of the wording. And that a byline naming several people answers for the one the reader asked about.

For a source's own articles it buys the same : the wording for one article, for several from one source and for several from several, which articles count as new, that what arrived here is what is asked about rather than what is dated today, that what is read, hidden or a second copy is left out, that a refusal leaves the source alone rather than saving a switch that can never fire, and that a decision arriving from another device does not announce that source's backlog.

The prompt itself was checked by hand, on the simulator, outside XCUITest : XCUITest does not surface the notification permission alert at all, and a test that waits for it waits for ever.
