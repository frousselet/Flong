//
//  AppearanceSettings.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The three answers to what a page is.
///
/// **It is under the reader's own face because a theme is about the reader.**
/// Everything that panel leads to is what belongs to the person rather than to
/// the page, and which face they want to read in is exactly that : it follows
/// them to their next device, like their name and like the body an article
/// opens on, and it says nothing about any feed they follow.
///
/// **Each name is set in its own theme's headline face.** A list of three words
/// in one face is a list that asks the reader to remember what `Solarized`
/// looked like ; a list where each word is drawn in the face it will give them
/// is a specimen, and choosing from a specimen takes no memory at all. The line
/// under each says what the colours do, which is the half a specimen cannot
/// show inside one row.
///
/// **A page of its own, and the page is three rows.** That is not a page spent
/// on nothing : the specimen is the whole point of the control, and three rows
/// each carrying a face and a sentence were three rows nobody could see at once
/// in the middle of a column of every other setting there is.
struct AppearanceSettings: View {
    @Bindable var model: AppModel
    /// The way out of the panel this page is pushed inside.
    let close: () -> Void

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.theme) {
                    ForEach(Theme.allCases) { candidate in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(candidate.headline(.body))
                            Text(candidate.explanation)
                                .font(candidate.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(candidate)
                    }
                } label: {
                    Text("Theme")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .themedRows()
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Appearance"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
    }
}
