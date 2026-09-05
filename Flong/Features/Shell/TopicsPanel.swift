//
//  TopicsPanel.swift
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
///
/// **A panel from the bottom, and no longer a page.** What a reader does here
/// is said about the page they are looking at, so the page stays behind the
/// panel while they say it : they nudge a subject, watch nothing happen to the
/// list, and flick the panel away. A screen pushed onto a stack put the front
/// page out of sight for the whole of that.
///
/// It stands taller than the notices beside it, which are one switch, and it
/// pulls up to the whole screen : fifty-two sections and however many of the
/// reader's own are a list to scroll, and a list to scroll wants the height a
/// reader chooses.

///
/// **Nothing in it paints a background.** A sheet is already inset from the
/// edges of the screen and rounded on all four corners ; a `List` paints its
/// own background edge to edge, over the rounded corners and down past the safe
/// area, which is what squares a floating panel off. The scroll view's own
/// background is hidden so the shape the system draws is the shape that shows,
/// and the rows keep theirs, which is what makes them read as rows.
struct TopicsPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var isAdding = false
    @State private var name = ""
    @State private var symbol = Topic.defaultSymbol
    /// The subject whose mark is being changed, where one is.
    @State private var marking: TopicPreferences.Known?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            subjects
        }
        .themed()
        // The reader's panel opens the whole way for this, holding as it does
        // a handful of rows against a list of every subject there is. The
        // modifier applies to the enclosing presentation while this page is on
        // the stack and gives it back on the way out.
        .presentationDetents([.large])
        // **A sheet and not an alert, now that there is a mark to pick.** An
        // alert holds a field and two buttons and nothing else : a grid of
        // fifty-odd glyphs in one is not something the system will draw, and a
        // subject added without a mark would wear the tag for ever unless the
        // reader found their way back to change it.
        .sheet(isPresented: $isAdding) {
            TopicEditor(name: $name, symbol: $symbol, isNaming: true) {
                Task { await model.addTopic(name, symbol: symbol) }
            }
        }
        .sheet(item: $marking) { topic in
            TopicEditor(name: .constant(topic.name), symbol: $symbol, isNaming: false) {
                Task { await model.setTopicSymbol(symbol, of: topic.name) }
            }
        }
        .task { await model.loadKnownTopics() }
    }

    /// What the panel is, what can be added to it, and the way out on the
    /// platform that needs one.
    private var head: some View {
        HStack(spacing: 14) {
            Text("Subjects")
                .font(theme.headline(.title3))

            Spacer(minLength: 8)

            Button {
                name = ""
                symbol = Topic.defaultSymbol
                isAdding = true
            } label: {
                Label("Add a subject", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
            }
            // An identifier beside the name, because the name is translated and
            // a test that looked for the English would pass here and fail on a
            // device set to the reader's own language.
            .accessibilityIdentifier("add-subject")

            PanelDismiss()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var subjects: some View {
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
        .scrollContentBackground(.hidden)
        .themedRows()
        .overlay {
            if model.knownTopics.isEmpty {
                ContentUnavailableView {
                    Label("No subjects yet", systemImage: "circle.grid.2x2")
                } description: {
                    Text(
                        OnDeviceModel.absence
                            ?? "Subjects appear once the model has read a page of stories. Yours can be added at any time."
                    )
                }
            }
        }
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
            // **A button on the reader's own, and a mark on the rest.** The
            // mark is where a reader looks to see what a subject wears, so it
            // is where they reach to change it ; a section's comes from the
            // catalogue and is the same on every device, so there is nothing to
            // press.
            Group {
                if topic.kind == .own {
                    Button {
                        symbol = topic.symbol
                        marking = topic
                    } label: {
                        mark(topic.symbol)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Change the mark of \(topic.name)"))
                } else {
                    mark(topic.symbol).accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: topic.name)
                // The band above says whose it is, so the line under the name
                // says only how much of the page it covers.
                Text("\(topic.stories) stories")
                    .font(theme.metadata)
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

    /// One subject's mark, at the size a row wears it.
    private func mark(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(.body, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 28)
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

/// Writing a subject, and picking the mark it wears.
///
/// **One sheet for both, because they are one decision.** A subject is a word
/// and a glyph : added without the glyph it wears the tag until the reader
/// finds their way back, and a reader who has just written `Typographie` is
/// exactly the person who knows what it should look like.
///
/// It opens on the same sheet when only the mark is being changed, with the
/// name shown and not offered : renaming a subject moves its stories and the
/// reader's opinion of it, which is a different decision and not one a symbol
/// picker may take by itself.
struct TopicEditor: View {
    @Binding var name: String
    @Binding var symbol: String
    /// Whether the name is being written, or only shown.
    let isNaming: Bool
    let done: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    /// Wide enough that the palette reads as a palette, narrow enough that no
    /// glyph is a hand's width from the one beside it.
    private static let columns = [GridItem(.adaptive(minimum: 54), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Editorial.rhythm) {
                    if isNaming {
                        TextField("Subject", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                    } else {
                        Text(verbatim: name)
                            .font(theme.headline(.title3))
                    }

                    Text("The model files stories under the subjects you have, and can write none of its own.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    palette
                }
                .padding(20)
            }
            .navigationTitle(isNaming ? Text("Add a subject") : Text("Mark"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        done()
                        dismiss()
                    } label: {
                        isNaming ? Text("Add") : Text("Done")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancel")
                }
            }
            .themed()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themed()
    }

    /// The marks a reader may pick from : what the sections wear, and nothing
    /// else. See ``StandardTopics/palette``.
    private var palette: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(StandardTopics.palette, id: \.self) { mark in
                Button {
                    symbol = mark
                } label: {
                    Image(systemName: mark)
                        .font(.system(.title3, weight: .regular))
                        .frame(width: 54, height: 54)
                        .foregroundStyle(mark == symbol ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(mark == symbol ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: mark))
                .accessibilityAddTraits(mark == symbol ? [.isSelected] : [])
            }
        }
    }
}
