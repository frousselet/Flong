//
//  PrivateCloudAgreement.swift
//  Flong
//
//  Created by François Rousselet on 21/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The one question asked before anything is put to Apple's own larger model.
///
/// **Its own sheet, and not the one that covers a service the reader
/// configured.** That one names a host they chose and an account they pay for,
/// and neither sentence is true here : there is no address, no key and no bill.
/// Answering one must not answer the other, so they are two.
///
/// **What it does not claim.** It does not say the articles stay on the device,
/// because they do not. It says where they go and what is done with them, and
/// leaves the reader to decide.
struct PrivateCloudAgreement: View {
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
                Text("They go to Private Cloud Compute, which is Apple's. Apple does not keep them.")
                Text(
                    "There is no account and nothing to pay. The limit is your device's, shared with everything else that uses it."
                )
                Text(
                    "This writes what you have not pointed somewhere else. Anything you chose yourself stays where you put it."
                )
                Text("Nothing is sent until you agree here. You can stop at any time.")
                Text("Every call is written down on this device.")

                VStack(spacing: 10) {
                    Button {
                        answer(true)
                    } label: {
                        Text("Start sending").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("private-cloud-consent-accept")

                    Button {
                        answer(false)
                    } label: {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("private-cloud-consent-decline")
                }
                .padding(.top, 8)
            }
            .font(theme.standfirst(.callout))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .editorialColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("private-cloud-consent")
    }
}
