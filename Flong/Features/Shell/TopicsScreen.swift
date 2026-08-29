//
//  TopicsScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Every subject, and what the reader has said about each.
///
/// The pills on the front page carry the subjects of the day, which is where a
/// reader forms an opinion and where saying it costs one press. This is the
/// other half : the whole list, including the subjects that have fallen off the
/// page, so that a reader who asked for less of something months ago can find it
/// again and take it back. A preference nobody can find is a preference nobody
/// can undo.
struct TopicsScreen: View {
    let model: AppModel

    var body: some View {
        List {
            if !model.knownTopics.isEmpty {
                Section {
                    ForEach(model.knownTopics) { topic in
                        row(topic)
                    }
                } header: {
                    Text("Subjects")
                } footer: {
                    Text(
                        "The system model reads the page and sorts it into subjects. Saying more or less of one moves it, and everything under it, up or down the front page."
                    )
                }
            }

            if model.knownTopics.contains(where: { $0.score != 0 }) {
                Section {
                    Button(role: .destructive) {
                        Task { await model.forgetEveryPreference() }
                    } label: {
                        Text("Forget every preference")
                    }
                }
            }
        }
        .navigationTitle(Text("Subjects"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if model.knownTopics.isEmpty {
                ContentUnavailableView {
                    Label("No subjects yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text(OnDeviceModel.absence ?? "Subjects appear once the model has read a page of stories.")
                }
            }
        }
        .task { await model.loadKnownTopics() }
    }

    private func row(_ topic: TopicPreferences.Known) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: topic.name)
                Text("\(topic.stories) stories")
                    .font(Editorial.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Three states, said in full : a stepper would ask the reader to
            // count presses, and the score is a means rather than the point.
            Picker(selection: preference(of: topic)) {
                Image(systemName: "arrow.down").tag(-1)
                Image(systemName: "minus").tag(0)
                Image(systemName: "arrow.up").tag(1)
            } label: {
                Text(verbatim: topic.name)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
        }
        .accessibilityElement(children: .contain)
    }

    /// The direction, rather than the number.
    ///
    /// A reader pressing the pill can nudge a subject three deep ; here they are
    /// choosing a side, and reading back three shades of the same side would be
    /// a control that says more than it lets them say.
    private func preference(of topic: TopicPreferences.Known) -> Binding<Int> {
        Binding(
            get: { topic.score.signum() },
            set: { direction in
                Task { await model.setPreference(of: topic.name, to: direction) }
            }
        )
    }
}
