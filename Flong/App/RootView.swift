//
//  RootView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers

/// The window content.
///
/// Everything hangs off the store, so a window without one has nothing to show
/// and says so rather than pretending to be empty.
struct RootView: View {
    let database: AppDatabase?

    var body: some View {
        if let database {
            AppShell(database: database)
        } else {
            ContentUnavailableView {
                Label("Storage unavailable", systemImage: "externaldrive.trianglebadge.exclamationmark")
            } description: {
                Text("Flong could not open its database.")
            }
        }
    }
}

#Preview {
    RootView(database: try? AppDatabase.inMemory())
}
