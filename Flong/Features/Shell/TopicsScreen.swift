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

    @State private var isAdding = false
    @State private var name = ""

    var body: some View {
        List {
            // Two bands, in the order a reader meets them : the ones they
            // wrote, then the sections they already knew before opening this.
            // There was a third, what the model had named itself ; it names
            // nothing now. A band with nothing in it is not drawn at all,
            // heading included.
            group(
                .own,
                titled: Text("Your own subjects"),
                saying: Text("Yours to add and to remove. The model reaches for them as readily as the sections.")
            )

            group(
                .standard,
                titled: Text("Standard subjects"),
                saying: Text(
                    "The sections every reader has. The model files each story under one or two of these, or of yours, and can write none of its own."
                )
            )

            if model.knownTopics.contains(where: { $0.score != 0 || $0.isOwn }) {
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
        .toolbar {
            ToolbarItem {
                Button {
                    name = ""
                    isAdding = true
                } label: {
                    Label("Add a subject", systemImage: "plus")
                }
            }
        }
        .alert("Add a subject", isPresented: $isAdding) {
            TextField("Subject", text: $name)
            Button("Add") { Task { await model.addTopic(name) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model files stories under the subjects you have, and can write none of its own.")
        }
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if model.knownTopics.isEmpty {
                ContentUnavailableView {
                    Label("No subjects yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text(
                        OnDeviceModel.absence
                            ?? "Subjects appear once the model has read a page of stories. Yours can be added at any time."
                    )
                }
            }
        }
        .task { await model.loadKnownTopics() }
    }

    /// One band of the list, or nothing when that nature has no subjects.
    @ViewBuilder
    private func group(_ kind: TopicKind, titled title: Text, saying footer: Text) -> some View {
        let topics = model.knownTopics.filter { $0.kind == kind }

        if !topics.isEmpty {
            Section {
                ForEach(topics) { row($0) }
            } header: {
                title
            } footer: {
                footer
            }
        }
    }

    @ViewBuilder
    private func row(_ topic: TopicPreferences.Known) -> some View {
        let content = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: topic.name)
                // The band above says whose it is, so the line under the name
                // says only how much of the page it covers.
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

        // A subject the reader wrote is theirs to take back. A standard one is
        // not a thing that was made, and one the model found would only be
        // found again on the next page : what a reader wants from those is the
        // preference rather than the deletion.
        if topic.kind == .own {
            content.swipeActions {
                Button(role: .destructive) {
                    Task { await model.removeTopic(topic.name) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            content
        }
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
