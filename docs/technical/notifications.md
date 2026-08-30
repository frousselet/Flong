# Notifications

Everything Flong may interrupt the reader for, and the rules it interrupts them under.

## Local, and only local

There is no server, so there is nobody to send a notification. Every one of these is written by the device that shows it, about something that device worked out for itself : it read its own page, found its own subject, and told its own reader. A second device may say the same thing at a different moment, or never, and that is correct rather than a drift to fix.

The `aps-environment` entitlement is there for `CKSyncEngine`, which uses a silent push to say that another device changed something. Nothing that arrives that way is ever shown to the reader.

## Permission is asked when the reader asks

Every switch starts off, and turning one on is what asks the system. A prompt at first launch is a prompt about something the reader has not seen yet, which is how an application gets refused permanently for a feature that would have been welcome later.

A refusal is final until the reader goes to the system settings : asking again does not prompt, it returns the refusal. So the switch goes back where it was and the screen says where the answer lives, which is the only honest thing an application can do about a refusal.

**What the reader wants is carried between devices ; whether a device may interrupt them is not.** The preference is a decision about themselves and travels through the iCloud key-value store like every other one ; the permission is the system's answer on one device and never travels. It is right that the two disagree : a reader may want the notices and have refused them on the Mac.

## New subjects

The first, and so far the only one.

The model files each story under the subjects the reader already has, and when nothing fits it names one. A subject it has never used before is usually a subject the press has just started covering, which is the kind of thing a reader watching a field wants to be told about.

**What counts as new** is a row written into `topic` by the model since this device last said anything. Three things are deliberately not new :

- **a subject the reader wrote themselves**, since telling somebody about a word they typed is the application repeating them back at them ;
- **a second spelling of one that exists**, since the vocabulary folds `cybersecurite` into `Cybersécurité` before writing anything, so nothing was written and there is nothing to announce ;
- **everything that existed before the reader turned the notices on**, since the watermark is stamped at that moment rather than at the beginning of time.

**The watermark is this device's own**, kept in `UserDefaults` and never carried. One that travelled would have the second device stay silent about what only the first had announced.

**Nothing interrupts a reader who is looking at the page it would be about.** A new subject appears as a pill on the front page, so a reader with Flong open has already seen it, and a notice about something they watched happen is a notice to dismiss for nothing. The watermark moves anyway : what it records is that the subject reached them, not that a notification was posted. Being told tomorrow about what they saw today would be worse than not being told.

**The title counts and the body lists, and the two always agree.** One subject is named under `New subject` ; several are counted in the title and listed in the body. A body showing the first few of a longer list is a small lie, and the system truncating a long one is the system's business rather than a reason to say less than the truth.

A tap opens the subject on the front page, when there is one subject to open. Several are not a place to go, and a tap that had to pick one of three would pick wrongly twice out of three times.

## Where it happens

The digest is rebuilt in three places : when a window opens, when the reader pulls, and in the background processing task. Only the last is a moment the reader is not looking, and it is the one this exists for.

**Both background tasks were dead when this was written.** They were registered while the application launched, as they have to be, against a box that nothing ever filled ; on iOS no request was ever submitted either, so the system had nothing to schedule. Both are fixed here, since a notice that can only fire while the reader is watching is a notice that never fires.

## Tapping one from a cold start

The delegate has to be in place before launching finishes, or a notification tapped from a cold start is never handed over. The window and its model do not exist that early, so `NotificationRouter` is set as the delegate in the application's own initializer and holds the answer until the window claims it, exactly as `BackgroundWorkBox` does for the background tasks.

## What is testable, and what is not

The delivery needs an authorization, a bundle and a device, none of which a test can rely on, and none of which is where the mistakes are. `Announcing` is the seam : `Notifier` is the system, `MemoryAnnouncer` is a list a test reads back.

What that buys is coverage of everything that can actually be wrong : the wording and the plural, the list that has to read well with one name and with five, which subjects count as new, that nothing is said twice, that nothing is said while the reader is reading and that it is not saved up for later either, that a refusal leaves the switch where it was, and that a reader who asked for nothing has their watermark left alone so that turning the notices on later starts from that moment.

The prompt itself was checked by hand, on the simulator, outside XCUITest : XCUITest does not surface the notification permission alert at all, and a test that waits for it waits for ever.
