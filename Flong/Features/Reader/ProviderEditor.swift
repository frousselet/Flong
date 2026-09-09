//
//  ProviderEditor.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One account being written down or changed.
///
/// A value rather than a set of `@State`s : the sheet is raised with one of
/// these, so the difference between adding and editing is what it was built
/// from and nothing else.
@Observable
final class ProviderDraft: Identifiable {
    /// What the model field holds when the reader would rather type a name.
    static let typedByHand = "\u{0000}typed"

    let id: UUID
    let isNew: Bool
    var kind: ProviderKind
    var name: String
    var address: String
    var key: String
    var model: String
    var typed: String
    var hasStoredKey: Bool
    var isReplacingKey = false

    var offered: [ProviderModel] = []
    var isFetching = false
    var isTesting = false
    var listTrouble: LocalizedStringResource?
    var probe: ProviderProbe?

    init(_ account: ProviderAccount?, hasStoredKey: Bool) {
        self.isNew = account == nil
        self.id = account?.id ?? .v7()
        self.kind = account?.kind ?? .openAICompatible
        self.name = account?.name ?? ""
        self.address = account?.origin?.absoluteString ?? ProviderKind.openAICompatible.address ?? ""
        self.key = ""
        self.model = account?.model ?? Self.typedByHand
        self.typed = account?.model ?? ""
        self.hasStoredKey = hasStoredKey
    }

    /// What the reader actually chose, whether from the list or by hand.
    var chosenModel: String {
        model == Self.typedByHand ? typed.trimmingCharacters(in: .whitespaces) : model
    }

    var canAsk: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isComplete: Bool {
        canAsk && !name.trimmingCharacters(in: .whitespaces).isEmpty && !chosenModel.isEmpty && url != nil
    }

    var url: URL? {
        let address = address.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: address), url.host() != nil else { return nil }
        return url
    }

    /// Whether the address will be carried in the clear to somewhere it should
    /// not be.
    var isPlainAndPublic: Bool {
        guard let url else { return false }
        return !LocalNetwork.allowsPlainHTTP(url)
    }

    var isPlainAndPrivate: Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "http" && LocalNetwork.allowsPlainHTTP(url)
    }

    var account: ProviderAccount {
        ProviderAccount(
            id: id,
            kind: kind,
            name: name.trimmingCharacters(in: .whitespaces),
            origin: url,
            model: chosenModel
        )
    }
}

/// Where a reader writes down a model of their own.
///
/// A sheet with its own stack : a pushed page has a Back button and nowhere
/// natural for a commit, and this one has both an answer and a way out.
struct ProviderEditor: View {
    let model: AppModel
    @Bindable var draft: ProviderDraft

    /// The way out, handed in rather than read from the environment.
    ///
    /// **A `DismissAction` read here closes the panel and not this sheet.** It
    /// is the same trap `PanelDismiss` records for a page pushed inside the
    /// reader's panel : a sheet raised from a navigation destination that is
    /// itself inside a sheet resolves the action to the outer one, and saving a
    /// provider put the reader back on the front page. The page that raised
    /// this one knows how to put it away, so it says so.
    let close: () -> Void

    @Environment(\.theme) private var theme

    @State private var isRemoving = false

    var body: some View {
        NavigationStack {
            Form {
                service
                secret
                models
                testing
                if !draft.isNew { removing }
            }
            .themedRows()
            #if os(macOS)
                .formStyle(.grouped)
            #endif
            .navigationTitle(Text(draft.isNew ? "Add a provider" : "Edit the provider"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // An identifier beside the name, because the name is
                    // translated and a test that looked for the English would
                    // pass here and fail on a device set to the reader's own
                    // language.
                    Button("Cancel") { close() }
                        .accessibilityIdentifier("provider-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(draft.account, key: draft.key.isEmpty ? nil : draft.key)
                        close()
                    }
                    .disabled(!draft.isComplete)
                    .accessibilityIdentifier("provider-save")
                }
            }
            .alert("Remove \(draft.name)?", isPresented: $isRemoving) {
                Button("Remove", role: .destructive) {
                    model.removeProvider(draft.id)
                    close()
                }
                .accessibilityIdentifier("provider-remove-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The tasks using it go back to this device. The key is deleted from the keychain.")
            }
        }
    }

    // MARK: - What it is

    private var service: some View {
        Section {
            Picker(selection: $draft.kind) {
                // Verbatim : the name of a format is the same in every language.
                Text(verbatim: "OpenAI").tag(ProviderKind.openAICompatible)
                Text(verbatim: "Anthropic").tag(ProviderKind.anthropic)
            } label: {
                Text("Kind")
            }
            .onChange(of: draft.kind) { _, kind in
                // The address is filled in once, and never over something the
                // reader typed.
                guard draft.address.isEmpty || ProviderKind.allCases.compactMap(\.address).contains(draft.address)
                else { return }
                draft.address = kind.address ?? ""
            }

            TextField(text: $draft.name) { Text("Name") }
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                .accessibilityIdentifier("provider-name")

            TextField(text: $draft.address) { Text(verbatim: "https://api.example.com/v1") }
                #if os(iOS)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("provider-address")

            if draft.isPlainAndPrivate {
                Label {
                    Text("Not encrypted. This only works on your own network.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(theme.metadata)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Service")
        } footer: {
            if draft.isPlainAndPublic {
                Text("An address outside your own network has to start with https.")
            } else {
                Text("Most services speak the OpenAI API. Anthropic has one of its own.")
            }
        }
    }

    // MARK: - The key

    /// **Never read back to the screen.** A secret feed address is shown in
    /// dots and read out on a deliberate tap, and the reason is that a reader
    /// has to be able to compare it against the platform's own page. A key is
    /// minted by the service, shown once by the service, and reissued at will :
    /// there is nothing to compare it against, so showing it buys nothing and
    /// costs the one thing a keychain is for.
    private var secret: some View {
        Section {
            if draft.hasStoredKey && !draft.isReplacingKey {
                Text("A key is stored")
                    .accessibilityIdentifier("provider-key-stored")
                Button("Replace the key") { draft.isReplacingKey = true }
            } else {
                SecureField(text: $draft.key) { Text("Key") }
                    #if os(iOS)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { fetch() }
                    .accessibilityIdentifier("provider-key")
            }
        } footer: {
            Text("The key goes to the keychain and is never shown again.")
        }
    }

    // MARK: - Which model

    private var models: some View {
        Section {
            Picker(selection: $draft.model) {
                ForEach(draft.offered) { offered in
                    // Verbatim : a model identifier is spelled the same
                    // everywhere.
                    Text(verbatim: offered.name ?? offered.id).tag(offered.id)
                }
                Text("Another model").tag(ProviderDraft.typedByHand)
            } label: {
                Text("Model")
            }

            if draft.model == ProviderDraft.typedByHand {
                TextField(text: $draft.typed) { Text(verbatim: "gpt-4o-mini") }
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("provider-model")
            }

            Button {
                fetch()
            } label: {
                HStack(spacing: 8) {
                    Label("Fetch the models", systemImage: "arrow.down.circle")
                    if draft.isFetching {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!draft.canAsk || draft.isFetching)
            .accessibilityIdentifier("provider-fetch")
        } footer: {
            if let trouble = draft.listTrouble {
                Text(trouble)
            } else {
                Text("Flong asks the service which models it offers. Type a name if it does not answer.")
            }
        }
    }

    // MARK: - Whether it answers

    private var testing: some View {
        Section {
            Button {
                test()
            } label: {
                HStack(spacing: 8) {
                    Label("Test this provider", systemImage: "checkmark.circle")
                    if draft.isTesting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!draft.isComplete || draft.isTesting)
            .accessibilityValue(draft.isTesting ? Text("Testing") : Text(verbatim: ""))
            .accessibilityIdentifier("provider-test")

            if let probe = draft.probe {
                outcome(probe)
            }
        } footer: {
            Text("The test sends one short sentence, and nothing of yours.")
        }
    }

    @ViewBuilder
    private func outcome(_ probe: ProviderProbe) -> some View {
        switch probe {
        case .answered(_, _, let dialect, let models):
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text("The service answered.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(.green)

                if dialect != .strictSchema {
                    Text("This service does not hold a model to a schema. Answers are checked here instead.")
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                }
                if models > 0 {
                    Text("\(models) models available")
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                }
            }

        case .trouble(let trouble):
            Label {
                Text(trouble.line)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)

        case .localNetworkRefused:
            Label {
                Text("iOS is not letting Flong reach your network. Settings, Flong, Local Network.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        }
    }

    private var removing: some View {
        Section {
            Button(role: .destructive) {
                isRemoving = true
            } label: {
                Text("Remove this provider")
            }
            .accessibilityIdentifier("provider-remove")
        }
    }

    // MARK: - Asking the service

    private func fetch() {
        guard draft.canAsk, !draft.isFetching else { return }
        draft.isFetching = true
        draft.listTrouble = nil

        Task {
            let answer = await model.models(of: draft.account, key: draft.key.isEmpty ? nil : draft.key)
            draft.isFetching = false

            switch answer {
            case .success(let models) where models.isEmpty:
                draft.listTrouble = "The service did not say which models it offers."
            case .success(let models):
                draft.offered = models
                if draft.chosenModel.isEmpty, let first = models.first { draft.model = first.id }
            case .failure(let trouble):
                draft.listTrouble = trouble.line
            }
        }
    }

    private func test() {
        guard draft.isComplete, !draft.isTesting else { return }
        draft.isTesting = true
        draft.probe = nil

        Task {
            draft.probe = await model.test(draft.account, key: draft.key.isEmpty ? nil : draft.key)
            draft.isTesting = false
        }
    }
}
