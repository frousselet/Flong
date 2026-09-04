//
//  BackgroundScheduler.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import Synchronization

#if os(iOS)
    import BackgroundTasks
#else
    import IOKit.ps
#endif

/// Asks the system for time, and uses whatever it gives.
///
/// Section 15 is clear about what this is worth : background refresh is
/// opportunistic by nature, the system decides alone according to activity,
/// battery and expected consumption, and the reader can turn it off. Permanent
/// freshness is not promised, and the interface never presents an unread count
/// as though it were real time. Returning to the foreground is the mechanism
/// that actually refreshes ; this is the bonus.
nonisolated enum BackgroundScheduler {
    /// The identifiers, which must also be in the Info.plist under
    /// `BGTaskSchedulerPermittedIdentifiers`. Without that, `submit` throws
    /// `notPermitted` and nothing ever runs.
    static let refreshIdentifier = "com.rslt.Flong.refresh"
    static let processingIdentifier = "com.rslt.Flong.processing"
    /// The one the reader starts themselves, and watches finish.
    static let continuedIdentifier = "com.rslt.Flong.continued"

    /// The edition of the moment, asked for at the hour it comes out.
    ///
    /// **Its own identifier, and not a stage of the full pass.** The full pass
    /// wants the mains and comes round every six hours with three quarters of
    /// an hour of jitter on top, which is right for vectorizing a corpus and
    /// wrong for a morning paper : a reader whose phone is not on charge at
    /// four in the morning would have had no edition at all. This one asks for
    /// a network and nothing else, at the boundary itself.
    static let editionIdentifier = "com.rslt.Flong.edition"

    /// About what a refresh is given, and all it should count on.
    static let refreshBudget: TimeInterval = 25

    /// What is kept back out of that budget for everything after the fetching.
    ///
    /// The watchdog below cancels the whole task when the budget runs out, and
    /// the fetching honours its own deadline between feeds while letting what is
    /// already in flight finish. Given the same instant to work to, the fetching
    /// therefore always returned at or after the watchdog fired, and the
    /// grouping, the reading and the one notice a refresh exists to post all ran
    /// inside a cancelled task : GRDB throws `CancellationError` from every read,
    /// so the pass fetched the articles and then could not say a word about
    /// them. The two clocks must not be the same clock.
    static let refreshTail: TimeInterval = 8

    /// What the fetching itself is given, which is the budget less the tail.
    static var fetchBudget: TimeInterval { refreshBudget - refreshTail }

    /// What the model's own work is given inside a full pass.
    ///
    /// The pass has minutes rather than seconds, and nothing here is urgent :
    /// the jobs are resumable, so what one pass does not get through the next
    /// one does. What the bound is for is that the headlines and the subjects
    /// share the time instead of the first of them taking all of it.
    static let fullPassBudget: TimeInterval = 5 * 60

    // MARK: - How often the whole of the work runs
    //
    // Read off Photos, which does the same kind of thing for the same kind of
    // reason and has had years to settle it. `photoanalysisd` declares its
    // heavy analysis as `RequiresExternalPower`, `Priority Maintenance`,
    // `ResourceIntensive`, on a six-hour `Interval` with a hundred-minute
    // `MinDurationBetweenInstances`, a forty-five minute `RandomInitialDelay`,
    // and a `GroupConcurrencyLimit` of one over a group named
    // `sequentialProcessing`. Four of those are available to an application and
    // are taken.
    //
    // Two are deliberately not. `PreventsDeviceSleep` is right for Photos,
    // which has hours of analysis to get through and nothing else to do it in ;
    // a feed reader holding a Mac awake to fetch three hundred feeds is a feed
    // reader nobody keeps. And Photos splits power from network across two
    // daemons, `cloudphotod` syncing on battery so long as there is a network
    // while `photoanalysisd` waits for the mains : Flong is asked for one pass
    // that does both, so it takes the stricter of the two conditions.

    /// Six hours, which is `photoanalysisd.backgroundanalysis`'s own interval.
    static let fullPassInterval: TimeInterval = 6 * 60 * 60

    /// The floor between two full passes, whatever the scheduler decides.
    ///
    /// Photos calls it `MinDurationBetweenInstances` and sets it to a hundred
    /// minutes against a six-hour interval. It is what stops a pass that was
    /// deferred, for want of power or of a network, from running again the
    /// moment it is rescheduled.
    static let fullPassFloor: TimeInterval = 100 * 60

    /// How much later than asked a full pass may begin.
    ///
    /// Photos jitters by up to forty-five minutes. It matters more here than it
    /// does there : a reader's devices all wake on the same schedule and would
    /// otherwise ask three hundred publishers for the same feeds at the same
    /// second, which section 8 has a per-device stagger to prevent for exactly
    /// this reason.
    static let fullPassJitter: TimeInterval = 45 * 60

    /// Where the moment of the last opportunistic refresh is written down.
    ///
    /// **Because nothing else records that one ran.** `BGTaskScheduler` gives an
    /// application no way to ask how it is doing : a reader whose system has
    /// decided to grant Flong no time, or who has turned Background App Refresh
    /// off, sees exactly what a reader with a working one sees, which is
    /// nothing. The notifications panel says when the last one was, and says so
    /// plainly when there has never been one.
    private static let lastRefreshKey = "flong.last-refresh"

    /// When the last opportunistic refresh ran, or `nil` if none ever has.
    static func lastRefresh(in defaults: UserDefaults = .standard) -> Date? {
        let stamp = defaults.double(forKey: lastRefreshKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Where the moment of the last full pass is written down.
    ///
    /// **On disk, and not only in memory.** It was a static held for the life
    /// of the process, which on iOS is minutes : every relaunch forgot that a
    /// pass had just run, so the floor guarded nothing across the launches it
    /// exists to guard across, and the next request could not be asked for at
    /// the right moment because nothing knew when the right moment was.
    private static let lastFullPassKey = "flong.last-full-pass"

    /// When the last full pass ran, so the floor can be kept.
    private static let lastFullPass = Mutex(Date.distantPast)

    /// When the last full pass ran, as far as this device remembers.
    static func lastFullPass(in defaults: UserDefaults = .standard) -> Date {
        let remembered = Date(timeIntervalSince1970: defaults.double(forKey: lastFullPassKey))
        return max(lastFullPass.withLock { $0 }, remembered)
    }

    private static func rememberTheFullPass(at date: Date, in defaults: UserDefaults = .standard) {
        lastFullPass.withLock { $0 = date }
        defaults.set(date.timeIntervalSince1970, forKey: lastFullPassKey)
    }

    /// The earliest a full pass may begin, counted from the last one rather
    /// than from now.
    ///
    /// A device that has just run one waits the whole interval. A device that
    /// has not run one for a day asks for one immediately : the wait is owed
    /// to the last pass, and starting it afresh every time anything asked was
    /// what starved the pass on a phone in daily use.
    static func nextFullPass(
        now: Date = Date(),
        jitter: TimeInterval = .random(in: 0...BackgroundScheduler.fullPassJitter)
    ) -> Date {
        max(lastFullPass().addingTimeInterval(fullPassInterval), now).addingTimeInterval(jitter)
    }
    /// Whether a pass is running, so two never are.
    ///
    /// Photos puts every heavy activity in one group with a concurrency limit
    /// of one. Here there are two, the half-hourly refresh and the full pass,
    /// and the full one fetches every feed a reader follows : the two running
    /// together would double what the publishers see.
    private static let isPassing = Mutex(false)

    /// Runs the work if this is a moment to run it, and says whether it did.
    ///
    /// The floor, the group of one, and the answer either way in one place, so
    /// the two platforms cannot drift apart on it.
    static func runFullPass(_ work: () async -> Void) async -> Bool {
        let now = Date()
        let mayRun = isPassing.withLock { passing -> Bool in
            guard !passing else { return false }
            guard now.timeIntervalSince(lastFullPass()) >= fullPassFloor else { return false }
            passing = true
            return true
        }
        guard mayRun else {
            Log.enrich.info("A full pass was asked for too soon after the last, and was left")
            return false
        }

        defer {
            rememberTheFullPass(at: Date())
            isPassing.withLock { $0 = false }
        }
        await work()
        return true
    }

    /// Forgets when the last pass ran, so a test can ask for another.
    static func forgetTheLastFullPass(in defaults: UserDefaults = .standard) {
        lastFullPass.withLock { $0 = .distantPast }
        defaults.removeObject(forKey: lastFullPassKey)
        defaults.removeObject(forKey: lastRefreshKey)
        isPassing.withLock { $0 = false }
    }

    /// The same group of one, for the half-hourly refresh.
    ///
    /// **Nothing runs in Low Power Mode.** The reader has told the system, in
    /// so many words, to stop doing things they did not ask for, and a feed
    /// reader waking the radio every half hour is exactly such a thing. What
    /// they did ask for still works : opening Flong refreshes, and pulling the
    /// list down refreshes.
    static func runRefresh(_ work: () async -> Void) async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            Log.enrich.info("A refresh stood aside for Low Power Mode")
            return
        }
        guard !isPassing.withLock({ $0 }) else {
            Log.enrich.info("A refresh stood aside for the full pass")
            return
        }
        await work()
        // Written down after the work rather than before it, so what the panel
        // shows is a refresh that happened and not one that was attempted.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
    }

    #if os(macOS)
        /// Whether the machine is running on the mains rather than on its
        /// battery.
        ///
        /// On iOS this is `BGProcessingTaskRequest.requiresExternalPower` and
        /// the system answers it. On macOS nothing asks it for you :
        /// `NSBackgroundActivityScheduler` finds an idle moment and has no
        /// opinion about where the power is coming from, so the question is put
        /// here.
        ///
        /// A machine that will not say counts as on the mains, which is the
        /// right way round : a desktop has no battery to report, and refusing
        /// to work on one because it did not answer would be refusing to work
        /// at all.
        static var isOnExternalPower: Bool {
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return true }
            guard let kind = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
                return true
            }
            return kind != kIOPSBatteryPowerValue
        }
    #endif

    #if os(iOS)
        /// Registers the handlers. Must happen before the application finishes
        /// launching, or the system refuses the identifier for the whole run.
        static func register(
            refresh: @escaping @Sendable () async -> Void,
            process: @escaping @Sendable () async -> Void,
            edition: @escaping @Sendable () async -> Void
        ) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
                handle(task, budget: refreshBudget) { await runRefresh { await refresh() } }
                schedule()
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
                handle(task, budget: nil) { _ = await runFullPass { await process() } }
                scheduleFullPass()
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedIdentifier, using: nil) { task in
                continued.withLock { $0.progress = (task as? BGContinuedProcessingTask)?.progress }
                handle(task, budget: nil) {
                    await process()
                    continued.withLock { $0.progress = nil }
                }
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: editionIdentifier, using: nil) { task in
                handle(task, budget: nil) { await edition() }
                // The next boundary is asked for by whatever knows the reader's
                // schedule, which is the model : the request submitted here
                // would be the floor and nothing more.
            }
        }

        /// Asks for the moment the next edition comes out.
        ///
        /// **A moment and not an interval.** An edition is a page made at an
        /// hour, so the request names that hour ; the system may of course be
        /// late, and it often will be, which is why the foreground path builds
        /// and names the edition too. Section 25 is explicit that background
        /// time is a bonus and the foreground is the mechanism, and nothing
        /// here forgets it.
        ///
        /// It asks for a network but not for the mains. A morning paper that
        /// only arrived on a phone left charging overnight would be a morning
        /// paper most readers never saw.
        static func scheduleEdition(at moment: Date?) {
            guard let moment else { return }
            let request = BGProcessingTaskRequest(identifier: editionIdentifier)
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = true
            request.earliestBeginDate = max(moment, Date(timeIntervalSinceNow: 60))
            submit(request)
        }

        /// The bar the system draws for the task the reader started.
        ///
        /// `BGContinuedProcessingTask` hands over a `Progress` and draws
        /// whatever is written into it, in its own interface. It is the system
        /// progress section 19 asks the initial import to run with, and without
        /// it the reader watches a bar that never moves for the ten minutes an
        /// account of thirty thousand articles takes.
        ///
        /// `Progress` is thread-safe and is not `Sendable`, which is the whole
        /// of what the box is for.
        private struct ContinuedProgress: @unchecked Sendable {
            var progress: Progress?
        }

        private static let continued = Mutex(ContinuedProgress())

        /// Moves that bar. Does nothing when the system did not take the task,
        /// which is the ordinary case and not a failure.
        static func report(done: Int, of total: Int) {
            guard total > 0 else { return }
            continued.withLock { held in
                held.progress?.totalUnitCount = Int64(total)
                held.progress?.completedUnitCount = Int64(min(done, total))
            }
        }
    #endif

    #if !os(iOS)
        /// The same call, doing nothing : a Mac has no task of this kind to
        /// draw a bar for, and the caller should not have to know that.
        static func report(done: Int, of total: Int) {}
    #endif

    #if os(iOS)

        /// Asks the system to see a long job through, with its own progress
        /// interface, after the reader started it.
        ///
        /// The task begins on a deliberate action and the system then commits to
        /// letting it finish. Section 15 also says this API is not reliable in
        /// practice, which is why the job it runs is resumable anyway and why a
        /// refusal is not a failure : the work carries on in the application
        /// instead, and again at the next launch.
        @discardableResult
        static func requestContinuedProcessing(title: String, subtitle: String) -> Bool {
            let request = BGContinuedProcessingTaskRequest(
                identifier: continuedIdentifier,
                title: title,
                subtitle: subtitle
            )
            request.strategy = .queue

            do {
                try BGTaskScheduler.shared.submit(request)
                return true
            } catch {
                Log.enrich.notice(
                    "The system would not take the continued task : \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }

        /// Asks for the opportunistic kind of time.
        ///
        /// **Only that kind.** It used to ask for the full pass in the same
        /// breath, and it is called on every return from the foreground and at
        /// every launch : each of those pushed the pass six hours and up to
        /// forty-five minutes further out, so on a phone anyone actually uses
        /// the pass was permanently starved and only ever ran after a night
        /// untouched. The pass asks for itself now, from its own handler and
        /// once at launch, against a moment written to disk.
        static func schedule(earliest: Date? = nil) {
            let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
            // **The moment a feed is actually due, where the store has been
            // asked**, and the floor a feed is held to anyway where it has not.
            // A flat fifteen minutes asked for time nobody could spend when
            // every feed was daily, and asked too late when one was hourly and
            // had just become due : the system reads this as the earliest
            // moment worth waking for, and telling it the truth is what makes
            // an opportunistic grant land on something.
            //
            // Never sooner than a minute, so a store where everything is
            // overdue asks for now rather than for the past, and never later
            // than the feed floor plus a day : a request nothing ever replaces
            // is how background refresh stops for good.
            let wanted = earliest ?? Date(timeIntervalSinceNow: RefreshSchedule.minimumInterval)
            request.earliestBeginDate = min(
                max(wanted, Date(timeIntervalSinceNow: 60)),
                Date(timeIntervalSinceNow: RefreshSchedule.maximumInterval)
            )
            submit(request)
        }

        /// Asks for the full pass, counting from when the last one actually
        /// ran rather than from now.
        ///
        /// A device that has not had a pass for a day asks for one now. Asking
        /// for one six hours out, as it did, meant the wait started again every
        /// time anything asked.
        static func scheduleFullPass(now: Date = Date()) {
            let request = BGProcessingTaskRequest(identifier: processingIdentifier)
            // A device at rest on charge, which is what this asks for and what
            // the system reads it as : overnight, on the desk, plugged in. It
            // is the one moment a reader is not waiting for anything, so it is
            // the moment to do the whole of the work rather than the urgent
            // part of it.
            request.requiresExternalPower = true
            // The pass fetches every feed, exchanges with iCloud and reads the
            // shared archives. It used to say it needed no network, from when
            // it only vectorized what was already here, and the system was
            // entitled to run the whole thing with no way to reach anything.
            request.requiresNetworkConnectivity = true
            // Six hours after the last pass, and up to forty-five minutes more,
            // which is what Photos asks for. The jitter is what keeps a
            // reader's devices from waking together and asking three hundred
            // publishers the same question at the same second.
            request.earliestBeginDate = Self.nextFullPass(now: now)
            submit(request)
        }

        private static func submit(_ request: BGTaskRequest) {
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // `notPermitted` here means the identifier is missing from the
                // Info.plist, which is a build mistake and not a runtime one.
                Log.enrich.error(
                    "\(request.identifier, privacy: .public) was refused : \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        /// Runs the work, and makes sure the system is told either way.
        ///
        /// A task that is never marked finished is a task the system remembers
        /// for the wrong reasons, and it hands out less time next time.
        ///
        /// **A pass that ran out of time is a success.** Every job here is
        /// resumable by construction : the work left is a question the store
        /// answers, so stopping between two batches loses nothing and the next
        /// grant carries on. Reporting a budgeted run as a failure, which is
        /// what `!Task.isCancelled` did on every single one of them, told the
        /// scheduler the opposite and taught it to grant time less often. That
        /// is the one thing a task whose budget keeps expiring least needs.
        ///
        /// The watchdog races the work rather than outliving it : it used to be
        /// a detached sleep that held the job for its whole budget even when
        /// the work had returned in a second.
        private static func handle(_ task: BGTask, budget: TimeInterval?, work: @escaping @Sendable () async -> Void) {
            let job = Task {
                if let budget {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await work() }
                        group.addTask { try? await Task.sleep(for: .seconds(budget)) }
                        // Whichever comes first ends the other : the work
                        // finishing cancels the clock, the clock running out
                        // cancels the work.
                        await group.next()
                        group.cancelAll()
                    }
                } else {
                    await work()
                }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { job.cancel() }
        }
    #else
        /// The macOS equivalent, which asks for the same two kinds of time.
        private nonisolated(unsafe) static var refreshActivity: NSBackgroundActivityScheduler?
        private nonisolated(unsafe) static var processingActivity: NSBackgroundActivityScheduler?
        private nonisolated(unsafe) static var editionActivity: NSBackgroundActivityScheduler?

        static func register(
            refresh: @escaping @Sendable () async -> Void,
            process: @escaping @Sendable () async -> Void,
            edition: @escaping @Sendable () async -> Void
        ) {
            // The editions, on the hour. `NSBackgroundActivityScheduler` finds
            // an idle moment rather than a named one, so this asks every hour
            // and the pass itself decides whether there is anything to do : an
            // edition already made and already named is one query and no work,
            // which is what makes asking often affordable.
            editionActivity = activity(identifier: editionIdentifier, interval: 60 * 60) {
                await edition()
            }

            // The same floor a feed is held to anyway, so a Mac left with its
            // window behind another one is asked as often as a phone is. What
            // reaches a publisher is still decided per feed.
            refreshActivity = activity(identifier: refreshIdentifier, interval: RefreshSchedule.minimumInterval) {
                await runRefresh { await refresh() }
            }
            processingActivity = activity(identifier: processingIdentifier, interval: fullPassInterval) {
                // What `requiresExternalPower` says on iOS, said here by hand.
                // `NSBackgroundActivityScheduler` picks an idle moment and has
                // no opinion about the power source, so a laptop on battery
                // would have run the whole pass, fetching every feed, on the
                // one power budget nobody wants spent.
                //
                // Deferred rather than skipped : the activity repeats, so the
                // next turn of it finds the machine plugged in or defers
                // again.
                guard isOnExternalPower else {
                    Log.enrich.info("The full pass waited for the mains")
                    return
                }
                _ = await runFullPass { await process() }
            }
        }

        static func schedule(earliest: Date? = nil) {}

        /// `NSBackgroundActivityScheduler` repeats on its own, so there is
        /// nothing to ask for a second time.
        static func scheduleFullPass(now: Date = Date()) {}

        /// `NSBackgroundActivityScheduler` repeats on its own, so there is
        /// nothing to ask for a second time.
        static func scheduleEdition(at moment: Date?) {}

        /// macOS has no equivalent, and needs none : an application that is open
        /// is an application that can simply do the work.
        @discardableResult
        static func requestContinuedProcessing(title: String, subtitle: String) -> Bool { false }

        private static func activity(
            identifier: String,
            interval: TimeInterval,
            work: @escaping @Sendable () async -> Void
        ) -> NSBackgroundActivityScheduler {
            let scheduler = NSBackgroundActivityScheduler(identifier: identifier)
            scheduler.repeats = true
            scheduler.interval = interval
            scheduler.tolerance = interval / 2
            scheduler.qualityOfService = .background

            scheduler.schedule { completion in
                Task {
                    await work()
                    completion(.finished)
                }
            }
            return scheduler
        }
    #endif
}
