# Long work, and the background

Two things in Flong take longer than a moment : fetching a thousand feeds nobody has ever fetched, and computing a vector for every kept article. Both have to survive being interrupted, because both will be.

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
| `BGAppRefreshTask` | refreshes what is due, about thirty seconds | opportunistic, never counted on |
| `BGProcessingTask` | vectorizes, purges, compacts, `requiresExternalPower` | minutes of work, on charge |
| `BGContinuedProcessingTask` | the reader starts it and watches it finish | iOS only, and refused often |
| `NSBackgroundActivityScheduler` | both of the first two, on macOS | |

Every identifier is declared in `Config/Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. Without that, `submit(_:)` throws `notPermitted` and nothing ever runs, which is a build mistake that looks exactly like a runtime one.

Registration happens in the application's initializer, before launching finishes, or the system refuses the identifiers for the whole run. The window fills in what the tasks should call once it exists, which is the one link between a task registered at launch and a model created later.

**Background refresh is opportunistic and is treated as a bonus.** Section 25 is explicit : the system decides alone according to activity, battery and expected consumption, and the reader can turn it off. Returning to the foreground is the mechanism that actually refreshes, and the interface never presents an unread count as though it were real time.

`BGContinuedProcessingTask` is submitted when the reader asks to finish an import, and a refusal is not a failure : the work carries on in the application instead, and again at the next launch. Section 15 says the API is not reliable in practice, and everything here is built so that it does not have to be.

## Vectors

Only the library is vectorized. A hundred and twenty five thousand vectors would cost hours of device time and would answer a question nobody asks of a cache.

- **The system's own sentence embeddings** do the work, on the device. They need no download, no account and no Apple Intelligence, which matters : section 14 treats the language model as a feature flag with a path that always works without it. A language the system cannot embed simply has no vector, and search falls back on matching words.
- **A vector is only comparable to vectors from the same model at the same revision.** Both travel with it. A vector whose pair does not match this device's is dropped and computed again, and the device that recomputes republishes it. Mixing revisions does not fail loudly ; it quietly returns nonsense.
- **Quantized to eight bits, scaled by the vector's own largest component.** A normalized vector of five hundred dimensions has components around a twentieth, so quantizing against the range minus one to one would spend most of the available values on nothing and lose a tenth of a percent of similarity ; scaled, it loses a hundredth of that. The scale is not stored, because reading a vector normalizes it again and a cosine does not care how long either vector was.
- **Five hundred bytes per article**, so about a megabyte for a whole library, which is what section 14 budgets for it in CloudKit.

## Searching by meaning

Cosine similarity over the whole library, which needs no index structure at this scale : a few thousand vectors against one is a few million multiplications.

The query is embedded **once per model the library holds**, not once. A search is three words long and has no language to detect ; guessing one would send a French question to an English model, which comes back with nothing rather than with an error.

## Filing the stories

One more of the same shape : the stories nobody has filed under a subject yet, one call to the model each. It is resumable for the reason the others are, and for one of its own : a page brings in more stories between two openings than any fixed handful would get through, so a job that stopped after a handful would leave a backlog that never emptied. It runs until there is nothing left, the time runs out, or the model gives up. A story is asked about once and stamped as asked, whatever came of it : one the model cannot file would otherwise sit at the head of a queue taken newest first and stop everything behind it, which is a job that never finishes and a page that never fills.
