//
//  PlacePicker.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Where the reader says which town they read from.
///
/// **Two ways in, and the typed one comes first in the design if not on the
/// screen.** Searching for a town needs no permission, works on a Mac with no
/// receiver in it and on a phone in aeroplane mode, and is the answer for a
/// reader who is on holiday and does not want their holiday recorded as where
/// they live. The device's own answer is the shortcut, not the road.
///
/// **Nothing is offered finer than a town.** ``PlaceSuggestions`` asks MapKit
/// for addresses down to a district and no further, so the list is towns and
/// countries : the question is which region the reader reads from, and a street
/// is not an answer to it and is not a thing to keep.
///
/// **It says what went wrong itself.** The shell's alert is two sheets below by
/// the time this is open, and an alert presented from under a sheet is one
/// nobody sees. Each of the three refusals leaves the reader in front of the
/// search, which is the thing that still works in all three cases.
struct PlacePicker: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var search = ""
    @State private var suggestions = PlaceSuggestions()
    @State private var isResolving = false
    @State private var failure: PlaceFailure?

    var body: some View {
        NavigationStack {
            List {
                fromTheDevice
                found
            }
            .themedRows()
            .navigationTitle(Text("Where you are"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $search, prompt: Text("City"))
            .onChange(of: search) { _, typed in suggestions.look(for: typed) }
            .overlay {
                // Only once the completer has answered : shown while it is
                // still thinking, it would say there is nothing every time the
                // reader types a letter.
                if !search.isEmpty, suggestions.suggestions.isEmpty, !suggestions.isLooking {
                    ContentUnavailableView.search(text: search)
                }
            }
            .alert(
                Text("Something went wrong"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { refusal in
                Text(refusal.message)
            }
        }
        .themed()
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    /// The shortcut : the device says where it is, once.
    private var fromTheDevice: some View {
        Section {
            Button {
                locate()
            } label: {
                HStack(spacing: 8) {
                    Label("Use my location", systemImage: "location")
                    if model.isLocating {
                        Spacer(minLength: 0)
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(model.isLocating || isResolving)
        } footer: {
            Text("Asked once, when you press it. What comes back is a town : the coordinate itself is never kept.")
        }
    }

    /// What MapKit is offering for what has been typed.
    @ViewBuilder
    private var found: some View {
        if !suggestions.suggestions.isEmpty {
            Section {
                ForEach(suggestions.suggestions) { suggestion in
                    Button {
                        choose(suggestion)
                    } label: {
                        row(suggestion)
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                }
            } header: {
                Text("Suggestions")
            }
        }
    }

    /// A town over the region and the country it is in.
    ///
    /// Verbatim, both lines : a place name is what MapKit called it in the
    /// reader's own language, and running it through the catalogue would be
    /// asking to translate a proper noun.
    private func row(_ suggestion: PlaceSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: suggestion.title)
            if !suggestion.subtitle.isEmpty {
                Text(verbatim: suggestion.subtitle)
                    .font(theme.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func locate() {
        Task {
            guard let refused = await model.locate() else {
                dismiss()
                return
            }
            failure = refused
        }
    }

    private func choose(_ suggestion: PlaceSuggestion) {
        guard !isResolving else { return }
        isResolving = true

        Task {
            let place = await suggestions.place(of: suggestion)
            isResolving = false

            guard let place else {
                failure = .unreadable
                return
            }
            model.setPlace(place)
            dismiss()
        }
    }
}
