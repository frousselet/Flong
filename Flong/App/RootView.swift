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

import SwiftUI

/// The window content.
///
/// The reading interface of section 16 of the specification lands with M0. Until
/// then the window states plainly that nothing is subscribed yet.
struct RootView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No feed yet", systemImage: "dot.radiowaves.up.forward")
        } description: {
            Text("Add a feed to start reading.")
        }
    }
}

#Preview {
    RootView()
}
