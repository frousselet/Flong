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

import OSLog
import SwiftUI

@main
struct FlongApp: App {
    /// The store, opened once for the lifetime of the process.
    ///
    /// Nothing reads it yet : the reading interface arrives with M0. Opening it
    /// at launch is what runs the migrations and creates the file with its data
    /// protection class, rather than leaving both to the first query.
    private let database: AppDatabase?

    init() {
        do {
            database = try AppDatabase.onDisk()
            Log.store.info("Store opened and migrated")
        } catch {
            database = nil
            Log.store.error("The store could not be opened : \(error, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 700)
        #endif
    }
}
