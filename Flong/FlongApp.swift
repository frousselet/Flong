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

import SwiftUI

@main
struct FlongApp: App {
    @State private var probe = ProbeModel()

    var body: some Scene {
        WindowGroup {
            ProbeView()
                .environment(probe)
        }
        #if os(macOS)
            .defaultSize(width: 720, height: 800)
        #endif
    }
}
