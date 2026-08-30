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

#if os(iOS)
    import BackgroundTasks
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

    #if os(iOS)
        /// Registers the handlers. Must happen before the application finishes
        /// launching, or the system refuses the identifier for the whole run.
        static func register(
            refresh: @escaping @Sendable () async -> Void, process: @escaping @Sendable () async -> Void
        ) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
                handle(task, budget: refreshBudget) { await refresh() }
                schedule()
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
                handle(task, budget: nil) { await process() }
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
            // Vectorizing is minutes of work, which is a phone on charge and
            // not a phone in a pocket.
            request.requiresExternalPower = true
            request.requiresNetworkConnectivity = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
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
            refreshActivity = activity(identifier: refreshIdentifier, interval: 30 * 60, work: refresh)
            processingActivity = activity(identifier: processingIdentifier, interval: 2 * 60 * 60, work: process)
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
