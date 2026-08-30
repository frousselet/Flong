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

    /// About what a refresh is given, and all it should count on.
    static let refreshBudget: TimeInterval = 25

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

    /// When the last full pass ran, so the floor can be kept.
    private static let lastFullPass = Mutex(Date.distantPast)
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
            guard lastFullPass.withLock({ now.timeIntervalSince($0) >= fullPassFloor }) else { return false }
            passing = true
            return true
        }
        guard mayRun else {
            Log.enrich.info("A full pass was asked for too soon after the last, and was left")
            return false
        }

        defer {
            lastFullPass.withLock { $0 = Date() }
            isPassing.withLock { $0 = false }
        }
        await work()
        return true
    }

    /// Forgets when the last pass ran, so a test can ask for another.
    ///
    /// The floor is measured against a moment held for the life of the process,
    /// which is right in an application and impossible to test around.
    static func forgetTheLastFullPass() {
        lastFullPass.withLock { $0 = .distantPast }
        isPassing.withLock { $0 = false }
    }

    /// The same group of one, for the half-hourly refresh.
    static func runRefresh(_ work: () async -> Void) async {
        guard !isPassing.withLock({ $0 }) else {
            Log.enrich.info("A refresh stood aside for the full pass")
            return
        }
        await work()
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
            refresh: @escaping @Sendable () async -> Void, process: @escaping @Sendable () async -> Void
        ) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
                handle(task, budget: refreshBudget) { await runRefresh { await refresh() } }
                schedule()
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
                handle(task, budget: nil) { _ = await runFullPass { await process() } }
                scheduleProcessing()
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedIdentifier, using: nil) { task in
                handle(task, budget: nil) { await process() }
            }
        }

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

        /// Asks for both kinds of time.
        static func schedule() {
            let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
            submit(request)
            scheduleProcessing()
        }

        private static func scheduleProcessing() {
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
            // Six hours and up to forty-five minutes more, which is what Photos
            // asks for. The jitter is what keeps a reader's devices from waking
            // together and asking three hundred publishers the same question at
            // the same second.
            request.earliestBeginDate = Date(
                timeIntervalSinceNow: fullPassInterval + .random(in: 0...fullPassJitter)
            )
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
        private static func handle(_ task: BGTask, budget: TimeInterval?, work: @escaping @Sendable () async -> Void) {
            let job = Task {
                await work()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { job.cancel() }

            if let budget {
                Task {
                    try? await Task.sleep(for: .seconds(budget))
                    job.cancel()
                }
            }
        }
    #else
        /// The macOS equivalent, which asks for the same two kinds of time.
        private nonisolated(unsafe) static var refreshActivity: NSBackgroundActivityScheduler?
        private nonisolated(unsafe) static var processingActivity: NSBackgroundActivityScheduler?

        static func register(
            refresh: @escaping @Sendable () async -> Void, process: @escaping @Sendable () async -> Void
        ) {
            refreshActivity = activity(identifier: refreshIdentifier, interval: 30 * 60) {
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

        static func schedule() {}

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
