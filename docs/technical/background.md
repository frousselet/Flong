# Long work, and the background

Two things in Flong take longer than a moment : fetching a thousand feeds nobody has ever fetched, and computing a vector for every kept article. Both have to survive being interrupted, because both will be.

## Two passes, and what tells them apart

**The opportunistic refresh** asks only the feeds that are due, within the politeness of `docs/technical/fetching.md`. It is what a phone in a pocket gets, and it is deliberately small : twenty-five seconds, a token bucket per host, and no promise that anything finishes. It asks for the moment a feed is actually due, which is what the system reads `earliestBeginDate` as ; how many opportunities it actually gets is the system's decision and not this one's.

**It groups what it fetched.** It used to fetch and stop there, so a phone in a pocket collected articles all day and the front page gained nothing from any of it until the next full pass or the next cold launch. Grouping is plain SQL over what has just arrived and costs a fraction of the fetching that preceded it. What it does not do is run the model : a backgrounded application's sessions are rate-limited hard, and a handful of refusals there used to silence the model for the whole of the process that followed. That work belongs to the full pass and to a window somebody is looking at.

**The full pass** runs when the device is at rest on the mains. Every feed a reader follows, then the enrichment, the purge, the index, and the exchange with iCloud, in that order so that everything downstream works on what has just arrived rather than on what was there this morning. It ends by reading back what the window shows, the front page included, so the page a reader opens in the morning is the one the pass built and not the one it replaced.

It did not refresh at all until it was asked to. It enriched, purged, indexed and exchanged what was already in the store, which is a reasonable thing to do on charge and is not what a reader means by a full refresh.

**The pass keeps its own clock, on disk, and asks for itself.** Both requests used to be submitted together, from a function called at every launch and on every return from the foreground, and each of those pushed the pass six hours and up to forty-five minutes further out : on a phone anyone actually uses it was permanently starved and only ever ran after a night untouched, which is exactly what a reader reported. It is asked for once at launch and thereafter only by its own handler, and its next moment is counted from when the last pass actually ran rather than from whenever something asked. A device that has not had one for a day asks for one now.

The moment of the last pass is written to disk rather than held in a static. Held in a static it was forgotten at every relaunch, which on iOS is minutes, so the hundred-minute floor guarded nothing across exactly the launches it exists to guard across.

**A refresh the reader asked for waits its turn ; one nobody watched stands aside.** Standing aside is right for a clock tick, which comes round again the moment a feed is due and which nobody saw refused. It is wrong for the menu command and wrong for a pull : the reader made a deliberate movement, the control comes straight back out, and as far as they can tell the application did nothing when they asked. Those wait for the pass already running, up to half a minute, and then take their turn.

**One refresh at a time, whichever of the six triggers asked for it.** There were three ways in and two of them shared a flag : a clock tick took one, the full pass took nothing at all, and the long jobs took a flag of their own. So the nightly pass and the five-minute clock could ask three hundred publishers the same question at the same second, each unaware of the other, and the reader's own command could land in the middle of both. The scheduler already refuses to start two of its own passes at once ; the same rule now sits where the two halves actually meet, in the model, taken by the outermost entry point only. What runs inside a pass, the first fetch and the vectors and the model's own work, is that pass's business and asks nobody. Being observable, the same gate is what a pull waits its turn behind rather than being refused where the reader cannot see it.

**A pass that ran out of time is a success.** Every job here is resumable by construction, so a partial pass is the ordinary outcome and not a failure. Reporting one as a failure, which a cancelled task did on every budgeted run, teaches the scheduler to grant time less often. The watchdog races the work rather than outliving it : it was a detached sleep that held the job for its whole budget even when the work had returned in a second.

**The edition is a third pass, and it asks for the least of the three.** A page made at an hour has to arrive at that hour, and the full pass cannot promise it : it wants the mains, comes round every six hours and jitters by three quarters of an hour on top, so a phone that is not left on charge would have had no morning paper. This one asks for a network and not for the mains, at the boundary itself, and fetches nothing at all : the collection has already brought the articles in, and what is left is to read the page, take the ten stories that matter most, put them to the model as one question and say so.

Being idempotent is what makes it safe. An edition already made and already named is one query and no work, so the same pass runs on the hour, whenever a window opens, and after every catch-up, and only the first of those does anything. That matters more than the task does : section 25 says background time is a bonus and the foreground is the mechanism, and an edition that only arrived when `BGTaskScheduler` felt like it would be an edition most readers never saw.

On macOS there is no moment to name, `NSBackgroundActivityScheduler` finding an idle one rather than a given one, so it is asked for every hour and the pass itself decides whether there is anything to do.

## What Photos does, and what of it is taken

`photoanalysisd` does the same kind of thing for the same kind of reason and has had years to settle it. What its launch agent declares, per activity :

| Declared | Value | Taken |
| -------- | ----- | ----- |
| `RequiresExternalPower` | `true` on every heavy activity | yes, both platforms |
| `Interval` | 21600, six hours | yes |
| `MinDurationBetweenInstances` | 6000, a hundred minutes | yes |
| `RandomInitialDelay` | 2700, forty-five minutes | yes |
| `GroupConcurrencyLimit` with `GroupName` | 1, over `sequentialProcessing` | yes, as one gate over both passes |
| `Priority` | `Maintenance` | `qualityOfService = .background`, its public equivalent |
| `ResourceIntensive`, `PowerNap` | `true` | no equivalent an application can declare |
| `PreventsDeviceSleep` | `true` | **no** |

**The jitter matters more here than it does there.** Photos is one library on one device. A reader's devices all wake on the same schedule and would otherwise ask three hundred publishers the same question at the same second, which is what section 8's per-device stagger exists to prevent. Forty-five minutes of slack costs the reader nothing at four in the morning.

**The floor is what makes a deferral safe.** A pass that could not run, for want of power or of a network, is rescheduled ; without a floor it would run the moment it was, and a laptop plugged in and unplugged twice in an evening would fetch everything three times.

**`PreventsDeviceSleep` is refused on purpose.** It is right for Photos, which has hours of analysis to get through and no other moment to do it in. A feed reader holding a Mac awake to fetch three hundred feeds is a feed reader nobody keeps, and the activity repeats : what it misses tonight it does tomorrow.

**Photos splits power from network and Flong does not.** `cloudphotod` synchronizes on battery so long as there is a network, `RequiresExternalPower` false and `RequiresNetworkConnectivity` true ; `photoanalysisd` waits for the mains and asks for no network at all. That split is the better design and it is two daemons. What was asked for here is one pass that both fetches and enriches, so it takes the stricter of the two conditions : the mains and a network. The opportunistic refresh is what covers a reader on battery.

**The network condition was wrong and is fixed.** The processing request said `requiresNetworkConnectivity = false`, from when it only vectorized what was already stored. It now fetches every feed, exchanges with iCloud and reads the shared archives, and the system was entitled to run the whole thing with no way to reach anything.

**On macOS the power question is asked by hand.** `NSBackgroundActivityScheduler` finds an idle moment and has no opinion about the power source, so `IOPSGetProvidingPowerSourceType` is consulted and a pass on battery is deferred rather than run. A machine that will not answer counts as on the mains : a desktop has no battery to report, and refusing to work on one for want of an answer would be refusing to work at all.

## The resume point is the data

Section 15 asks for idempotent batches, a persisted resume point and automatic resumption at the next launch. Flong has the first and the third, and deliberately not the second.

**What is left to do is a question the store already answers.** The feeds never fetched are the ones with no `last_success_at`. The kept articles needing a vector are the ones whose vector is missing or was made by a model this device no longer runs. A checkpoint written beside them could only ever disagree with them, and a checkpoint that disagrees is worse than none, because it is believed.

So a job is a queue the store computes, a batch, and a count of what is left. Stopping between two batches loses nothing. Nothing has to be cleaned up after a crash, a force quit or an expiration, and resumption is not a special path : it is the ordinary one, run again.

## The jobs

| Job | Queue | Batch |
| --- | ----- | ----- |
| first fetch | feeds never fetched and not quarantined | twelve feeds |
| vectorize | kept articles with no current vector | fifty articles |

A feed that refuses to be fetched does not hold the queue for ever : three refusals quarantine it, and a quarantined feed is no longer work.

## Asking the system for time

| API | What it does | What it is worth |
| --- | ------------ | ---------------- |
| `BGAppRefreshTask` | refreshes what is due, announces it and groups it, about twenty-five seconds | opportunistic, never counted on, asked for at the moment a feed is due |
| `BGProcessingTask` | vectorizes, purges, compacts, `requiresExternalPower` | minutes of work, on charge |
| `BGProcessingTask` | makes and names the edition, a network and no mains | seconds of work, at the hour |
| `BGContinuedProcessingTask` | the reader starts it and watches it finish | iOS only, and refused often |
| `NSBackgroundActivityScheduler` | both of the first two, on macOS | |

Every identifier is declared in `Config/Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. Without that, `submit(_:)` throws `notPermitted` and nothing ever runs, which is a build mistake that looks exactly like a runtime one.

Registration happens in the application's initializer, before launching finishes, or the system refuses the identifiers for the whole run. The window fills in what the tasks should call once it exists, which is the one link between a task registered at launch and a model created later.

**The budget is not one clock but two.** The watchdog cancels the whole task when the twenty-five seconds run out, and the fetching honours its own deadline between feeds while letting what is already in flight finish. Given the same instant to work to, the fetching therefore always returned at or after the watchdog had fired, and everything after it ran inside a cancelled task : GRDB throws `CancellationError` from every read, so a pass fetched its articles and then could not group them, could not read who they were about, and could not say a word about any of it. Eight seconds are held back out of the budget for the tail, so the two clocks are never the same clock.

**And a task that finds no window does the work anyway.** The window fills the box in from its own `.task`, which runs when a view appears. An application the system launches into the background for a processing task may never render one, and the task then awaited a closure nobody had set and did nothing at all, silently : the one pass that fetches every feed a reader follows, skipped on exactly the occasions it exists for, with no log line to say so. The store is open by the time anything is registered, so the box keeps it and builds a model of its own when no window has offered a better one.

That model is told two things a window would have told it. It is not reading, since there is no window and nobody to interrupt : born believing otherwise, it suppressed every notification the pass existed to post. And it is given the two iCloud engines, which are started from the window's own task : without them the nightly pass that exists to exchange with iCloud exchanged nothing, and the filings notice could not tell the reader's own additions from anybody else's. What is left to the window is what only a window needs : offering to the pool, publishing the member cards, and hearing about an invitation.

**It asks for the next grant at the moment a feed is due.** The request named a flat fifteen minutes, which is the floor a feed is held to and says nothing about this reader's feeds : a store of daily papers woke the system four times an hour to find nothing, and an hourly wire was fetched a quarter of an hour after it published. The handler still asks for the floor, before anything has read the store, and the pass replaces that request with one naming the moment `FeedRefresh.nextDue()` gives back. Submitting again under one identifier replaces rather than adds, so the floor is what stands whenever the pass did not run at all. `docs/technical/fetching.md` sets out how the moment is worked out and why it had to be made stable before anything could sleep until it.

**Background refresh is opportunistic and is treated as a bonus.** Section 25 is explicit : the system decides alone according to activity, battery and expected consumption, and the reader can turn it off. Returning to the foreground is the mechanism that actually refreshes, and the interface never presents an unread count as though it were real time.

`BGContinuedProcessingTask` is submitted when the reader asks to finish an import, and a refusal is not a failure : the work carries on in the application instead, and again at the next launch. Section 15 says the API is not reliable in practice, and everything here is built so that it does not have to be.

## Vectors

Only the marked articles are vectorized. Hundreds of thousands of vectors would cost hours of device time and would answer a question nobody asks of an article they never looked twice at.

- **The system's own sentence embeddings** do the work, on the device. They need no download, no account and no Apple Intelligence, which matters : section 14 treats the language model as a feature flag with a path that always works without it. A language the system cannot embed simply has no vector, and search falls back on matching words.
- **A vector is only comparable to vectors from the same model at the same revision.** Both travel with it. A vector whose pair does not match this device's is dropped and computed again, and the device that recomputes republishes it. Mixing revisions does not fail loudly ; it quietly returns nonsense.
- **Quantized to eight bits, scaled by the vector's own largest component.** A normalized vector of five hundred dimensions has components around a twentieth, so quantizing against the range minus one to one would spend most of the available values on nothing and lose a tenth of a percent of similarity ; scaled, it loses a hundredth of that. The scale is not stored, because reading a vector normalizes it again and a cosine does not care how long either vector was.
- **Five hundred bytes per article**, so about a megabyte for all of them together, which is what section 14 budgets for them in CloudKit.

## Searching by meaning

Cosine similarity over every vector there is, which needs no index structure at this scale : a few thousand vectors against one is a few million multiplications.

The query is embedded **once per model the vectors were made with**, not once. A search is three words long and has no language to detect ; guessing one would send a French question to an English model, which comes back with nothing rather than with an error.

## Filing the stories

One more of the same shape : the stories nobody has filed under a subject yet, one call to the model each. It is resumable for the reason the others are, and for one of its own : a page brings in more stories between two openings than any fixed handful would get through, so a job that stopped after a handful would leave a backlog that never emptied. It runs until there is nothing left, the time runs out, or the model gives up. A story is asked about once and stamped as asked, whatever came of it : one the model cannot file would otherwise sit at the head of a queue taken newest first and stop everything behind it, which is a job that never finishes and a page that never fills.
