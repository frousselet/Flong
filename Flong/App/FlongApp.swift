//
//  FlongApp.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import SwiftUI
import UserNotifications

@main
struct FlongApp: App {
    /// What the background tasks call. Set once the window has a model, since
    /// the work belongs to it.
    static let work = BackgroundWorkBox()

    /// The one delegate this application has, and the one thing it is for.
    ///
    /// An invitation to a shared collection is handed over by the system to a
    /// delegate and to nothing else : there is no modifier and no scene phase
    /// that hears it. See ``ShareAcceptance``.
    #if os(iOS)
        @UIApplicationDelegateAdaptor(ShareAppDelegate.self) private var delegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(ShareAppDelegate.self) private var delegate
    #endif

    /// The store, opened once for the lifetime of the process.
    ///
    /// Opening it at launch is what runs the migrations and creates the file
    /// with its data protection class, rather than leaving both to the first
    /// query.
    private let database: AppDatabase?

    init() {
        do {
            database = try AppDatabase.onDisk()
            Log.store.info("Store opened and migrated")
        } catch {
            database = nil
            Log.store.error("The store could not be opened : \(error, privacy: .public)")
        }

        // Handed the store before anything is registered, so a task that fires
        // before any window exists has something to work with.
        FlongApp.work.open(database)

        // Registration has to happen before launching finishes, or the system
        // refuses the identifiers for the whole run.
        BackgroundScheduler.register(
            refresh: { await FlongApp.work.refresh() },
            process: { await FlongApp.work.process() }
        )

        // Same deadline, different reason : a notification tapped from a cold
        // start is handed over once, to whoever is the delegate by the time
        // launching finishes, and dropped if nobody is. Setting it asks for
        // nothing and prompts for nothing.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView(database: database)
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 700)
        #endif
    }
}

/// Holds what the background tasks should call, once there is something to call.
///
/// The tasks are registered while the application launches, before any window
/// and any model exists. This is the one link between the two, and it is empty
/// until the window fills it in.
final class BackgroundWorkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var refreshWork: (@Sendable () async -> Void)?
    private var processWork: (@Sendable () async -> Void)?
    private var database: AppDatabase?
    private var standIn: AppModel?

    func set(refresh: @escaping @Sendable () async -> Void, process: @escaping @Sendable () async -> Void) {
        lock.withLock {
            refreshWork = refresh
            processWork = process
        }
    }

    /// The store, so the work can be done even if no window ever asks for it.
    func open(_ database: AppDatabase?) {
        lock.withLock { self.database = database }
    }

    func refresh() async {
        // The system's clock started when it called the handler, and preparing a
        // model of our own can wait on iCloud : the fetch works to that instant
        // and not to whatever is left once we are ready.
        let started = Date()
        guard let work = lock.withLock({ refreshWork }) else {
            await standInModel()?.backgroundRefresh(from: started)
            return
        }
        await work()
    }

    func process() async {
        guard let work = lock.withLock({ processWork }) else {
            await standInModel()?.backgroundProcessing()
            return
        }
        await work()
    }

    /// The one model this process has.
    ///
    /// **One, and not one per thing that asks.** The window used to build its
    /// own and the background tasks another, which was harmless while the
    /// second did nothing but read. It is not harmless now that it starts the
    /// iCloud engines : two `CKSyncEngine` instances on one private database
    /// both persist their serialized state into the single `sync_state` row, so
    /// whichever writes second overwrites a state that knew about the first
    /// one's queued records, and those records are never sent. A launch the
    /// system made into the background followed by the reader opening the
    /// application is the ordinary way to get both.
    ///
    /// Built here rather than in the window because this is the one thing that
    /// exists before a window does and outlives one going away.
    @MainActor
    func model(for database: AppDatabase) -> AppModel {
        lock.withLock {
            if let standIn { return standIn }

            let made = AppModel(database: database)
            // A model is born believing the reader is looking at it, which is
            // what stops it interrupting somebody about a page they have open.
            // Whoever wants it read otherwise says so ; the window does, from
            // its own scene phase.
            made.isReading = false
            standIn = made
            return made
        }
    }

    /// A model for a launch that has no window, with the engines started.
    ///
    /// **The window fills this box in from its own `.task`, which runs when a
    /// view appears.** An application the system launches into the background
    /// for a processing task may never render one, and the task then awaited a
    /// closure nobody had set and did nothing at all, silently : the one pass
    /// that fetches every feed a reader follows, skipped on exactly the
    /// occasions it was designed for, with no log line to say so.
    ///
    /// **The engines are started here, once.** They are started from the
    /// window's own task otherwise, so a windowless pass exchanged nothing with
    /// iCloud and could not tell the reader's own filings from anybody else's.
    /// Starting them suspends for two round trips, and the model is claimed
    /// before that : a second task arriving in the gap would otherwise have
    /// built a second model and a second pair of engines.
    @MainActor
    private func standInModel() async -> AppModel? {
        guard let database = lock.withLock({ database }) else {
            Log.enrich.error("A background task had neither a window nor a store to work with")
            return nil
        }

        let claimed = lock.withLock { standIn == nil }
        let model = model(for: database)
        guard claimed else { return model }

        Log.enrich.notice("A background task ran without a window, against a model of its own")
        await model.startSyncEngines()
        return model
    }
}
