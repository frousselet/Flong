//
//  ModelSettings.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Who writes what, and the accounts the reader brought of their own.
///
/// **Two lists and nothing else.** What the model does, four rows, each naming
/// the model that does it ; and the providers themselves, each a name, an
/// address, a key in the keychain and a model. Everything else on the page
/// hangs off one of the two : the calls are what the second did on behalf of
/// the first, and the last row is the way to stop all of it at once.
///
/// **Four pickers and not four pages.** Four values on one screen is one
/// glance ; four pages is four menus for four menus. A row reading `use this
/// one for everything` was left out : it has to say something for a state where
/// one of the four differs from the others, and that state is the whole point
/// of a model per task.
///
/// **It is in the card that holds what the reader is offered from outside this
/// device**, beside the popular feeds and the sites they are signed in to. It
/// is the third row there that involves an account of theirs somewhere else,
/// and it is the one thing under their own face that sends the news itself
/// anywhere.
struct ModelSettings: View {
    let model: AppModel
    /// The way out of the panel this page is pushed inside.
    let close: () -> Void

    @Environment(\.theme) private var theme

    /// **One sheet and not two.** Two `.sheet` modifiers on one view is a
    /// thing SwiftUI accepts and does not honour : only the last of them is
    /// ever presented, and what the other one asked for is lost. The editor and
    /// the consent are therefore one state with two cases.
    @State private var presenting: Presenting?
    @State private var isStopping = false

    /// What is over the page, where anything is.
    enum Presenting: Identifiable {
        case editor(ProviderDraft)
        /// A choice waiting on the reader's answer to one question.
        case consent(task: ModelTask, choice: ModelChoice, host: String)

        var id: String {
            switch self {
            case .editor(let draft): "editor-\(draft.id)"
            case .consent(let task, _, _): "consent-\(task.rawValue)"
            }
        }
    }

    var body: some View {
        Form {
            tasks
            providers
            calls
            stopping
        }
        .themedRows()
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Models"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
        .sheet(item: $presenting) { presenting in
            switch presenting {
            case .editor(let draft):
                ProviderEditor(model: model, draft: draft) { self.presenting = nil }
                    .themed()
            case .consent(let task, let choice, let host):
                ModelConsent(host: host) { agreed in
                    self.presenting = nil
                    guard agreed else { return }
                    model.agreeToSendToProviders()
                    model.point(task, at: choice)
                }
                .themed()
            }
        }
        .alert("Stop sending anything?", isPresented: $isStopping) {
            Button("Stop sending", role: .destructive) { model.stopSendingToProviders() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every task goes back to this device. Your providers and their keys are kept.")
        }
        .task { model.loadProviders() }
    }

    // MARK: - What the model does

    /// The four things a model is asked here, each pointed where the reader
    /// wants it.
    ///
    /// **A line under a row, and only where there is something to say.** A
    /// picker reading `on this device` on a device with no Apple Intelligence
    /// is a setting that looks set and does nothing, which is the same failure
    /// the front page fixed by saying why it has no edition.
    private var tasks: some View {
        Section {
            ForEach(ModelTask.allCases, id: \.self) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Picker(selection: choice(for: task)) {
                        Text("On this device").tag(ModelChoice.onDevice)
                        // The reader's own name for their own account, so it is
                        // never translated.
                        ForEach(model.providers) { provider in
                            Text(verbatim: provider.name).tag(ModelChoice.provider(provider.id))
                        }
                        Text("No model").tag(ModelChoice.nothing)
                    } label: {
                        Text(task.title)
                    }

                    if let absence = model.absence(of: task) {
                        Text(absence)
                            .font(theme.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("model-task-\(task.rawValue)")
            }
        } header: {
            Text("What the model does")
        } footer: {
            Text("Each of these uses Apple Intelligence, one of your providers, or nothing at all.")
        }
    }

    /// Where the consent is asked, which is here and not before the first call.
    ///
    /// Three of the four run inside a background pass, which has no window to
    /// ask in. This is also the one place the reader can act on the answer.
    /// Refusing leaves the picker where it was.
    private func choice(for task: ModelTask) -> Binding<ModelChoice> {
        Binding(
            get: { model.choice(of: task) },
            set: { wanted in
                guard case .provider(let id) = wanted, !model.sendsToProviders else {
                    model.point(task, at: wanted)
                    return
                }
                guard let account = model.providers.first(where: { $0.id == id }) else { return }
                presenting = .consent(task: task, choice: wanted, host: account.host)
            }
        )
    }

    // MARK: - The accounts the reader brought

    private var providers: some View {
        Section {
            ForEach(model.providers) { provider in
                row(provider)
            }

            Button {
                presenting = .editor(ProviderDraft(nil, hasStoredKey: false))
            } label: {
                Label("Add a provider", systemImage: "plus")
            }
            .accessibilityIdentifier("add-provider")
        } header: {
            Text("Providers")
        } footer: {
            Text("Your own account, on a service you pay for. Flong has none and sends nothing on its own.")
        }
    }

    /// One provider : what the reader called it, and the fact that would
    /// surprise them.
    ///
    /// The second line is the address and the model, or, where something has
    /// gone wrong with it, what went wrong : a key that expired in the night
    /// has to be visible rather than silently costing them the better half of
    /// their front page.
    private func row(_ provider: ProviderAccount) -> some View {
        Button {
            presenting = .editor(ProviderDraft(provider, hasStoredKey: model.hasKey(for: provider)))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: provider.name)

                Group {
                    if let trouble = model.trouble(with: provider) {
                        Label {
                            Text(trouble.line)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    } else {
                        // A host and a model identifier are spelled the same in
                        // every language.
                        Text(verbatim: "\(provider.host) · \(provider.model)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(theme.metadata)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("provider-row-\(provider.id.uuidString)")
        .swipeActions {
            Button(role: .destructive) {
                model.removeProvider(provider.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - What went out

    @ViewBuilder
    private var calls: some View {
        if !model.providers.isEmpty {
            Section {
                NavigationLink(value: ReaderPage.providerCalls) {
                    HStack {
                        Text("Outgoing calls")
                        Spacer(minLength: 8)
                        Text(model.providerCallCount, format: .number)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("provider-calls")
            } footer: {
                Text("Every call is written down here, on this device.")
            }
            .task { await model.loadProviderCalls() }
        }
    }

    /// The way back out of all of it, in one press.
    ///
    /// **Not a card of red glass.** Nothing here is deleted : the providers and
    /// their keys stay, the four tasks come home, and a reader who changes
    /// their mind points them back. The one command that takes something away
    /// for good is on the data page, and it is the only one that earns the
    /// material.
    @ViewBuilder
    private var stopping: some View {
        if model.sendsToProviders {
            Section {
                Button(role: .destructive) {
                    isStopping = true
                } label: {
                    Text("Stop sending anything")
                }
                .accessibilityIdentifier("stop-sending")
            } footer: {
                Text("Puts every task back on this device.")
            }
        }
    }
}
