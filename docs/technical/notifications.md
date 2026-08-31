# Notifications

Everything Flong may interrupt the reader for, and the rules it interrupts them under.

## Local, and only local

There is no server, so there is nobody to send a notification. Every one of these is written by the device that shows it, about something that device worked out for itself : it read its own page, found its own subject, and told its own reader. A second device may say the same thing at a different moment, or never, and that is correct rather than a drift to fix.

The `aps-environment` entitlement is there for `CKSyncEngine`, which uses a silent push to say that another device changed something. Nothing that arrives that way is ever shown to the reader.

## Where the switches are

A panel from the bottom, opened by the bell beside the sources, in the leading corner of every section a reader reads in. It was a line in the reader's menu leading to a screen of its own, and one switch does not want two presses and a way back : a reader who turns a notice on is answering a question and going back to what they were reading, which is still behind the panel while they answer.

There is no master switch. A list of two switches with a third above them that overrules both is a list where nobody is sure what is on, and the system already has that switch, in the place a reader looks for it.

## Permission is asked when the reader asks

Every switch starts off, and turning one on is what asks the system. A prompt at first launch is a prompt about something the reader has not seen yet, which is how an application gets refused permanently for a feature that would have been welcome later.

A refusal is final until the reader goes to the system settings : asking again does not prompt, it returns the refusal. So the switch goes back where it was and the screen says where the answer lives, which is the only honest thing an application can do about a refusal.

**What the reader wants is carried between devices ; whether a device may interrupt them is not.** The preference is a decision about themselves and travels through the iCloud key-value store like every other one ; the permission is the system's answer on one device and never travels. It is right that the two disagree : a reader may want the notices and have refused them on the Mac.

## New stories

The first, and so far the only one.

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

## Where it happens

The digest is rebuilt wherever articles arrive : at launch, on the clock, on returning to the foreground, on the reader's own command, in the opportunistic background refresh and in the full pass. Only the background ones are moments the reader is not looking, and they are what this exists for.

**Both background tasks were dead when this was written.** They were registered while the application launched, as they have to be, against a box that nothing ever filled ; on iOS no request was ever submitted either, so the system had nothing to schedule. Both are fixed here, since a notice that can only fire while the reader is watching is a notice that never fires.

## Tapping one from a cold start

The delegate has to be in place before launching finishes, or a notification tapped from a cold start is never handed over. The window and its model do not exist that early, so `NotificationRouter` is set as the delegate in the application's own initializer and holds the answer until the window claims it, exactly as `BackgroundWorkBox` does for the background tasks.

## What is testable, and what is not

The delivery needs an authorization, a bundle and a device, none of which a test can rely on, and none of which is where the mistakes are. `Announcing` is the seam : `Notifier` is the system, `MemoryAnnouncer` is a list a test reads back.

What that buys is coverage of everything that can actually be wrong : the wording and the plural, the headline leading rather than being buried, the written line taking the place of the newsrooms when there is one, the middle dot rather than commas, which stories count as new, that nothing is said twice, that nothing is said while the reader is reading and that it is not saved up for later either, that a refusal leaves the switch where it was, and that a reader who asked for nothing has their watermark left alone so that turning the notices on later starts from that moment.

The prompt itself was checked by hand, on the simulator, outside XCUITest : XCUITest does not surface the notification permission alert at all, and a test that waits for it waits for ever.
