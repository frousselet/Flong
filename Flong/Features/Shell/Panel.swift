//
//  Panel.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What every panel opened from the leading corner has in common.
///
/// Three of them now : the sources, the subjects and the notices. They are
/// short sheets over the page rather than screens pushed in front of it,
/// because what a reader does in each is said about the page behind them and
/// they go back to it directly afterwards.
nonisolated enum Panel {
    /// How tall one holding a list stands before the reader asks for more.
    ///
    /// A height of its own rather than `.medium`, which is measured off the
    /// bottom of the screen and takes the panel's lower corners with it : a
    /// panel with two square corners reads as the page having been cut off
    /// rather than as something laid over it.
    static let tall: CGFloat = 540
}

/// The way out a Mac needs, and nothing on the platforms that do not.
///
/// A sheet on iOS is flicked away, and the indicator at the head of the panel
/// is what says so. A Mac sheet cannot be flicked and would strand the reader
/// with no way out at all, so the button stands there and only there : one on
/// both platforms would be a control saying what the gesture already says on
/// the one where the gesture exists.
struct PanelDismiss: View {
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    var body: some View {
        #if os(macOS)
            Button {
                dismiss()
            } label: {
                Text("Done").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
        #endif
    }
}
