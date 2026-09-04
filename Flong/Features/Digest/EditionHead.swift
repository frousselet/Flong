//
//  EditionHead.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What an edition says about itself, over the ten stories on it.
///
/// **The masthead of the page, and it is written.** A front page that was
/// rebuilt on every fetch had nothing to put here : there was no page, only the
/// newest sixty stories in an order that shifted under the reader. An edition
/// is made at an hour and named, so it can say what it is and what is in it
/// before the reader has read a headline.
///
/// The two lines are the model's own, in the reader's own language, and they
/// carry the same mark a story's line carries when a model wrote it. Nothing
/// here is ever an editor's own words rearranged : an edition with no headline
/// of its own is not shown at all, which is what makes the mark honest.
struct EditionHead: View {
    let edition: Edition
    let openArchive: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Editorial.tightRhythm) {
            HStack(spacing: 6) {
                Text(edition.slot.title)
                Text(verbatim: "·")
                Text(edition.openedAt, format: .dateTime.hour().minute())
            }
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)

            if let title = edition.title {
                Text(verbatim: title)
                    .font(theme.headline(.title))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary = edition.summary {
                // The same mark a story's line wears, in the same place and for
                // the same reason : section 14 asks that anything a model wrote
                // says so, and the page says it in front of the sentence rather
                // than in words beside it.
                (Text(Image(systemName: "sparkles")).foregroundStyle(.secondary)
                    + Text(verbatim: " ")
                    + Text(verbatim: summary))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("Written by the model : \(summary)"))
            }

            Button(action: openArchive) {
                Label("Previous editions", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Editorial.rhythm)
        .padding(.bottom, Editorial.tightRhythm)
    }
}

/// What stands where an edition would, when there is not one.
///
/// **Three absences, and never one word for all three.** A device that cannot
/// run the model will never have an edition and has to be told so plainly ; one
/// whose model is still downloading will have one shortly ; and one whose
/// reader has switched every edition off has asked for this. A page that said
/// `no edition` to all three would be a page working exactly as it should and
/// looking exactly like a page that is broken.
struct NoEdition: View {
    let hasSchedule: Bool
    let openSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No edition yet", systemImage: "newspaper")
        } description: {
            if !hasSchedule {
                Text("You have switched every edition off. The wire still holds everything that arrives.")
            } else if let absence = OnDeviceModel.absence {
                Text(absence)
            } else {
                Text("The next edition is being written. It appears once every headline on it is.")
            }
        } actions: {
            if !hasSchedule {
                Button("Edition times") { openSettings() }
            }
        }
    }
}
