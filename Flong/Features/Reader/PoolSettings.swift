//
//  PoolSettings.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the reader offers the other readers, and everything that follows from
/// having said yes.
///
/// **The one thing under the reader's own face that sends something outside
/// their own account.** Everything else there is theirs and stays theirs : a
/// name, a face, a town, a theme. This publishes a list of addresses into the
/// database every copy of Flong reads, so what it publishes and what it never
/// publishes are both written under the switch rather than left for the reader
/// to guess.
///
/// **Their identity in the pool is shown, and is meant to be handed over.** It
/// is opaque, it says nothing about them, and it is the only thing a roster can
/// name : a reader asking to be believed on their own has to be able to say who
/// they are, and this is the whole of how.
///
/// **A page of its own, and it earns one.** Five sections can stand here, four
/// of them lists : who the reader brought in, who the author vouched for, who
/// was cut out and which addresses are withheld. Threaded into a single column
/// of settings they were most of that column, for a subject a reader who never
/// turned the switch on has nothing to do with.
struct PoolSettings: View {
    let model: AppModel
    /// The way out of the panel this page is pushed inside.
    let close: () -> Void

    @Environment(\.theme) private var theme

    @State private var sponsoringCode = ""
    @State private var trustingCode = ""
    @State private var banningCode = ""

    var body: some View {
        Form {
            sharing
            if model.isSponsoredIntoPool { sponsoring }
            if model.mayDecideForThePool { deciding }
        }
        .themedRows()
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Popular feeds"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
    }

    /// Whether the reader offers what they follow to everybody else.
    private var sharing: some View {
        Section {
            Toggle(isOn: contributes) {
                Text("Share the sources I follow")
            }

            if model.contributesToPool == true, let identity = model.poolIdentity {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your contributor code")
                    Text(verbatim: identity)
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .swipeActions {
                    ShareLink(item: identity) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }

                if !model.isSponsoredIntoPool {
                    Label {
                        Text("Waiting for somebody to bring you in")
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(theme.metadata)
                    .foregroundStyle(.orange)
                }
            }
        } footer: {
            if model.contributesToPool == true, !model.isSponsoredIntoPool {
                Text("Nothing of yours is published until a member brings you in.")
            } else {
                Text("Only addresses. Never your name, a secret address or a source behind a password.")
            }
        }
    }

    /// Who this reader brought into the pool.
    ///
    /// **Shown to everybody who is in, and not only to the author.** The pool
    /// grows by sponsorship rather than by one person handing out every
    /// invitation, so this is an ordinary section of an ordinary page for
    /// anybody it applies to.
    ///
    /// The footer says what a sponsorship costs before one is made, because
    /// cutting somebody out cuts everybody who came in through them, and
    /// somebody vouching for a stranger should know that first.
    private var sponsoring: some View {
        Section {
            ForEach(Array(model.sponsoredContributors).sorted(), id: \.self) { code in
                contributorRow(code) {
                    Task { await model.stopSponsoring(code) }
                }
            }

            field($sponsoringCode, prompt: Text("Contributor code"), add: Text("Sponsor")) { code in
                Task { await model.sponsor(code) }
            }
        } header: {
            Text("Readers you brought in")
        } footer: {
            Text("Cutting one of them out cuts everybody they brought in.")
        }
    }

    /// What the author decided, on the one device that may decide it.
    private var deciding: some View {
        Group {
            Section {
                ForEach(Array(model.trustedContributors).sorted(), id: \.self) { creator in
                    contributorRow(creator) {
                        Task { await model.setTrustedContributors(model.trustedContributors.subtracting([creator])) }
                    }
                }

                field($trustingCode, prompt: Text("Contributor code"), add: Text("Trust")) { code in
                    Task { await model.setTrustedContributors(model.trustedContributors.union([code])) }
                }
            } header: {
                Text("Vouched for")
            } footer: {
                Text("What they follow is suggested straight away.")
            }

            Section {
                ForEach(Array(model.bannedContributors).sorted(), id: \.self) { creator in
                    contributorRow(creator) {
                        Task { await model.lift(creator) }
                    }
                }

                field($banningCode, prompt: Text("Contributor code"), add: Text("Ban")) { code in
                    Task { await model.ban(code) }
                }
            } header: {
                Text("Cut out")
            } footer: {
                Text("What they offer counts for nobody, and nor does what anybody they brought in offers.")
            }

            if !model.blockedAddresses.isEmpty {
                Section {
                    ForEach(model.blockedAddresses) { blocked in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: blocked.url ?? blocked.digest)
                                .font(theme.metadata)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            if blocked.url == nil {
                                Text("Withheld from another device")
                                    .font(theme.metadata)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.unblock(blocked) }
                            } label: {
                                Label("Allow again", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                } header: {
                    Text("Withheld addresses")
                } footer: {
                    Text("Never suggested, whoever follows them.")
                }
            }
        }
    }

    /// One contributor code, and the way to take it off the list it is on.
    private func contributorRow(_ value: String, remove: @escaping () -> Void) -> some View {
        Text(verbatim: value)
            .font(theme.metadata)
            .lineLimit(1)
            .truncationMode(.middle)
            .swipeActions {
                Button(role: .destructive, action: remove) {
                    Label("Remove", systemImage: "trash")
                }
            }
    }

    /// A field that takes a contributor code and a button that acts on it.
    private func field(
        _ text: Binding<String>,
        prompt: Text,
        add: Text,
        action: @escaping (String) -> Void
    ) -> some View {
        HStack {
            TextField(text: text) { prompt }
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

            Button {
                let code = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                text.wrappedValue = ""
                guard !code.isEmpty else { return }
                action(code)
            } label: {
                add.font(.subheadline)
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var contributes: Binding<Bool> {
        Binding(
            get: { model.contributesToPool == true },
            set: { wanted in Task { await model.setContributingToPool(wanted) } }
        )
    }
}
