//
//  AddressParametersView.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Saying which parameters of a feed's addresses carry the subscription.
///
/// **The reader says, because Flong cannot tell.** A platform that hands out a
/// per-subscriber feed puts the subscriber in the query string, and so does a
/// site that lets a reader pick a section : `?token=` and `?format=rss` look
/// exactly alike from here. `docs/technical/feed-identity.md` already settled
/// the consequence for identity, keeping the query string because it *selects
/// the feed on plenty of sites* ; a heuristic that stripped it to be safe would
/// collapse two subscriptions into one and hand somebody a link to the wrong
/// page.
///
/// **The question is asked against real addresses**, which is the only form in
/// which it can be answered. A list of parameter names in the abstract is a
/// list of things nobody recognizes ; a list showing what each one holds, on
/// this reader's own feed, is a question with an obvious answer.
///
/// **What a parameter holds is shown masked.** The whole reason for this screen
/// is that some of these are secrets, and a screen that printed them to be read
/// over a shoulder would be a strange place to keep one.
struct AddressParametersView: View {
    let model: AppModel
    let feedID: UUID
    /// What its addresses look like, for the reader to recognize them by.
    let feedURL: URL

    @State private var found: [AddressParameter] = []
    @State private var secret: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if found.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No parameters", systemImage: "link")
                        } description: {
                            Text("Neither this feed's address nor its articles carry any.")
                        }
                    }
                } else {
                    Section {
                        ForEach(found) { parameter in
                            Toggle(
                                isOn: Binding(
                                    get: { secret.contains(parameter.name) },
                                    set: { isSecret in
                                        if isSecret {
                                            secret.insert(parameter.name)
                                        } else {
                                            secret.remove(parameter.name)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: parameter.name)
                                    Text(verbatim: parameter.masked)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } header: {
                        Text("Parameters on this feed's addresses")
                    } footer: {
                        Text(
                            "What you mark here is taken off any address that leaves this device, and nothing else is. Nothing is removed on a guess : a parameter selects a feed or a filter as often as it names a subscriber."
                        )
                    }
                }
            }
            .navigationTitle(Text("Address parameters"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let chosen = secret
                        Task {
                            await model.setSecretParameters(chosen, for: feedID)
                            dismiss()
                        }
                    }
                }
            }
            .task {
                found = await model.addressParameters(of: feedID, feedURL: feedURL)
                secret = await model.secretParameters(of: feedID)
            }
        }
    }
}

/// One parameter a reader is being asked about.
nonisolated struct AddressParameter: Identifiable, Hashable, Sendable {
    /// The name, as the address spells it.
    let name: String
    /// What it holds, with most of it hidden.
    let masked: String

    var id: String { name }

    /// A value with enough of it left to be recognized and not enough to be
    /// used.
    ///
    /// The first two characters and the length. `format=rss` stays readable
    /// enough to be recognized as the harmless thing it is, and a forty
    /// character token says only that it is forty characters long.
    static func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "•", count: max(value.count, 1)) }
        return value.prefix(2) + String(repeating: "•", count: min(value.count - 2, 12))
    }
}
