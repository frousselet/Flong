//
//  ModelConsent.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the reader is told before anything of theirs leaves the device.
///
/// **Asked at the moment a task is first pointed at a service, and not at the
/// first call.** Three of the four things a model does here run inside a
/// background pass, and a background pass has no window to ask in : `ask before
/// the first call` is not implementable for the three that matter. Assignment
/// is also the moment they are standing in the one screen where they can act on
/// the answer.
///
/// **A sheet and not an alert.** There are six sentences, and an alert cannot
/// hold six legibly at an accessibility type size.
///
/// **Two answers stacked and never side by side.** They are not the same length
/// in any language, and a row of two makes one wrap while the other sits on a
/// line, which reads as one being the important one for a reason nobody can
/// name.
struct ModelConsent: View {
    /// The host the reader just chose, named out loud.
    let host: String
    let answer: (Bool) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What leaves this device")
                    .font(theme.headline(.title2))

                Text(
                    "Flong sends headlines and the first lines under them, including those of papers you pay for. Never the whole article."
                )
                Text("Search sends the sentence you type, and nothing else.")
                // The host is interpolated as a string and not as a `Text` :
                // interpolating a `Text` builds a key the catalogue does not
                // have, so the one sentence naming where the news goes was the
                // one sentence still in English on a French device.
                Text("They go to \(host).")
                Text("The account is yours. Flong has none, and pays for nothing.")
                Text("Nothing is sent until you agree here. You can stop at any time.")
                Text("Every call is written down on this device.")

                VStack(spacing: 10) {
                    Button {
                        answer(true)
                    } label: {
                        Text("Start sending").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("provider-consent-accept")

                    Button {
                        answer(false)
                    } label: {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("provider-consent-decline")
                }
                .padding(.top, 8)
            }
            .font(theme.standfirst(.callout))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .editorialColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("provider-consent")
    }
}
