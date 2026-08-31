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
        guard let work = lock.withLock({ refreshWork }) else {
            await standInModel()?.backgroundRefresh()
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

    /// A model of the box's own, for a launch that has no window.
    ///
    /// **The window fills this box in from its own `.task`, which runs when a
    /// view appears.** An application the system launches into the background
    /// for a processing task may never render one, and the task then awaited a
    /// closure nobody had set and did nothing at all, silently : the one pass
    /// that fetches every feed a reader follows, skipped on exactly the
    /// occasions it was designed for, with no log line to say so.
    ///
    /// The store is open by then either way, so the work is done against a
    /// model of its own. It is built once and kept, and it is used only while
    /// no window has offered anything better.
    @MainActor
    private func standInModel() -> AppModel? {
        if let standIn = lock.withLock({ standIn }) { return standIn }
        guard let database = lock.withLock({ database }) else {
            Log.enrich.error("A background task had neither a window nor a store to work with")
            return nil
        }

        Log.enrich.notice("A background task ran without a window, against a model of its own")
        let model = AppModel(database: database)
        lock.withLock { standIn = model }
        return model
    }
}
