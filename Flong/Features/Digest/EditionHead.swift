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
/// **The masthead of the page.** A front page that was rebuilt on every fetch
/// had nothing to put here : there was no page, only the newest sixty stories
/// in an order that shifted under the reader. An edition is made at an hour, so
/// it can say what is in it before the reader has read a headline.
///
/// **The dateline and a list, and nothing over them.** An edition carried a
/// name of its own and every real page showed the same thing : the name was the
/// list said again in fewer words. A front page has never had a name, and the
/// three attempts at one are recorded in `docs/technical/digest.md`.
///
/// The points are the model's own, in the reader's own language. An edition
/// with none is not shown at all.
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

            if !edition.points.isEmpty {
                points
            }

            Button(action: openArchive) {
                Label("Previous editions", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            // An identifier beside the name, because the name is translated and
            // a test that looked for the English would pass here and fail on a
            // device set to the reader's own language.
            .accessibilityIdentifier("edition-archive")
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Editorial.rhythm)
        .padding(.bottom, Editorial.tightRhythm)
    }

    /// The few things worth knowing, one per line.
    ///
    /// **A list and not a paragraph.** Asked for two or three sentences over
    /// ten stories the model wrote one clause per story and joined them with
    /// commas, and the line under the headline ran to seven items and eight
    /// lines of type. A front page has always answered this the same way.
    ///
    /// **No glyph in front of it.** The story rows carry one, and there it says
    /// something : a story's line is the model's or its publisher's, and the
    /// mark is how a reader tells which. Nothing on an edition's head is ever
    /// anybody else's, an edition existing only where the model wrote the whole
    /// of it, so a mark here answers a question nobody can ask. It is still
    /// said, to VoiceOver, where a statement costs no ink.
    ///
    /// The list is set with air around it. Five points at the spacing of a
    /// paragraph is a block, and a block is the thing this replaced.
    private var points: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(edition.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // A rule rather than a bullet character : the page is set
                    // as an editor would set it, and a round dot is a control
                    // panel's mark.
                    Rectangle()
                        .frame(width: 14, height: 1)
                        .foregroundStyle(.tertiary)
                        .offset(y: -5)
                    Text(verbatim: point)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Written by the model : \(edition.points.joined(separator: ". "))"))
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
