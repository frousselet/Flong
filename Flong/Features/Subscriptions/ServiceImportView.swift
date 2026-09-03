//
//  ServiceImportView.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Brings a FreshRSS account in.
///
/// Three steps, and the reader is only ever looking at one of them : sign in,
/// choose what to take, watch it arrive. Nothing is written until the middle
/// step is over, so a reader who changes their mind at the picker has changed
/// nothing.
///
/// **The screen holds the reader only when it has to.** An import of thirty
/// thousand articles is minutes of network, and the system will usually see it
/// through after they have put the phone away : where it agrees to, the bar says
/// so and the screen can be closed. Where it refuses, the bar takes the whole
/// screen and asks them to stay, because leaving really would stop it.
struct ServiceImportView: View {
    let model: AppModel

    /// Which of the three the reader is looking at.
    private enum Step: Hashable {
        case signingIn
        /// An import written down and not finished, offered before anything else.
        case resuming
        case choosing
        case working
    }

    @State private var step: Step = .signingIn
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false

    /// The streams the reader ticked, by the identifier the service gave them.
    @State private var chosen: Set<String> = []
    /// What this device already follows, so a row can say so.
    @State private var followed: Set<URL> = []
    @State private var wantsArticles = true
    @State private var depth: ImportDepth = .fiveHundred
    @State private var wantsFavourites = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            content
                // The name of the thing, which is not translated and is what
                // an inline bar with a button on either side has room for :
                // `Importer depuis FreshRSS` was drawn as `Importer dep...`,
                // and the reader has just pressed that line to get here.
                .navigationTitle(Text(verbatim: "FreshRSS"))
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(step == .working && !model.importRunsInBackground)
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
        #endif
        .task {
            followed = await model.followedAddresses()
            if model.pendingImport != nil { step = .resuming }
            if model.serviceProgress != nil { step = .working }
        }
        // The import carries on whether or not this screen is open, so the
        // screen follows it rather than driving it.
        .onChange(of: model.serviceProgress == nil) { _, isOver in
            if isOver, step == .working { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .signingIn: signIn
        case .resuming: resume
        case .choosing: picker
        case .working: working
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if step != .working || model.importRunsInBackground {
                Button("Close") { dismiss() }
                    .disabled(isSigningIn)
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            switch step {
            case .signingIn:
                Button("Sign in", action: openTheAccount)
                    .disabled(isSigningIn || address.isEmpty || username.isEmpty || password.isEmpty)
            case .choosing:
                Button("Import", action: start)
                    .disabled(chosen.isEmpty)
            case .resuming, .working:
                EmptyView()
            }
        }
    }

    // MARK: - Signing in

    private var signIn: some View {
        Form {
            Section {
                TextField(text: $address) {
                    Text("Address of your FreshRSS")
                }
                #if os(iOS)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("service-address")

                TextField(text: $username) {
                    Text("Username")
                }
                #if os(iOS)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                SecureField(text: $password) {
                    Text("API password")
                }
                #if os(iOS)
                    .textContentType(.password)
                #endif
            } footer: {
                Text(
                    "In FreshRSS, allow API access under Authentication, then set an API password in your profile. It is not the one you sign in to the site with."
                )
            }

        }
        .formStyle(.grouped)
        .themedRows()
        .disabled(isSigningIn)
        .overlay {
            if isSigningIn { ProgressView().controlSize(.large) }
        }
        // Under the form rather than in a section of its own, as the sign-in
        // page of a site says the same kind of thing : it is a promise about
        // the whole screen and not a setting on it, and a card holding one
        // sentence reads as a row the reader is meant to press.
        .safeAreaInset(edge: .bottom) {
            Text(
                "Flong reads the account once. It never signs in again on its own, changes nothing there, and keeps no link with the server."
            )
            .font(theme.metadata)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func openTheAccount() {
        isSigningIn = true

        Task {
            if await model.signInToService(address: address, username: username, password: password) {
                chosen = Set(
                    model.serviceSubscriptions.compactMap { $0.url?.isEmpty == false ? $0.id : nil }
                )
                password = ""
                step = .choosing
            }
            isSigningIn = false
        }
    }

    // MARK: - Choosing what to take

    private var picker: some View {
        Form {
            Section {
                ForEach(model.serviceSubscriptions) { subscription in
                    row(subscription)
                }
            } header: {
                HStack {
                    Text("\(model.serviceSubscriptions.count) subscriptions")
                    Spacer(minLength: 8)
                    Button("All") {
                        chosen = Set(model.serviceSubscriptions.compactMap { $0.url?.isEmpty == false ? $0.id : nil })
                    }
                    Button("None") { chosen = [] }
                }
                .buttonStyle(.borderless)
            } footer: {
                Text("A source you already follow keeps the name and the settings you gave it here.")
            }

            Section {
                Toggle(isOn: $wantsArticles) {
                    Text("Bring their articles too")
                }
                if wantsArticles {
                    Picker(selection: $depth) {
                        ForEach(ImportDepth.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    } label: {
                        Text("How much")
                    }
                }
            } footer: {
                Text(
                    "What was read stays read, and nothing you have already read here is undone. Everything can be tens of thousands of articles and takes several minutes."
                )
            }

            Section {
                Toggle(isOn: $wantsFavourites) {
                    Text("Bring the favourites")
                }
            } footer: {
                Text("A favourite lands where its source is one you follow. The others are counted and left.")
            }
        }
        .formStyle(.grouped)
        .themedRows()
    }

    private func row(_ subscription: GoogleReaderSubscription) -> some View {
        let isTicked = chosen.contains(subscription.id)
        let title = subscription.title?.isEmpty == false ? subscription.title ?? "" : subscription.url ?? ""
        let canonical = subscription.url.flatMap { try? FeedURL.canonical($0) }
        let isFollowed = canonical.map(followed.contains) ?? false

        return Button {
            if isTicked { chosen.remove(subscription.id) } else { chosen.insert(subscription.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isTicked ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    // The publisher's own name, which is not translated.
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    if isFollowed {
                        Text("Already followed")
                            .font(theme.metadata)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(canonical == nil)
        .accessibilityAddTraits(isTicked ? [.isSelected] : [])
    }

    private func start() {
        step = .working
        Task {
            await model.startServiceImport(
                chosen: chosen,
                depth: depth,
                wantsArticles: wantsArticles,
                wantsFavourites: wantsFavourites
            )
        }
    }

    // MARK: - An import left unfinished

    private var resume: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("An import is waiting to be finished")
                .font(theme.headline(.title3))

            if let job = model.pendingImport {
                // The reader's own server, which is not translated.
                Text(verbatim: job.account.host)
                    .font(theme.metadata)
                    .foregroundStyle(.secondary)
            }

            Text("Nothing already brought in is fetched again. It carries on from where it stopped.")
                .font(theme.metadata)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button("Finish it now") {
                step = .working
                Task { await model.resumeServiceImport() }
            }
            .buttonStyle(.borderedProminent)

            Button("Give up on it", role: .destructive) {
                Task {
                    await model.abandonServiceImport()
                    dismiss()
                }
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Watching it arrive

    /// The whole screen while it runs, which is what the reader asked for when
    /// they cannot leave : a bar in a corner would be an invitation to go
    /// somewhere else, and going somewhere else is what stops it.
    private var working: some View {
        VStack(spacing: 20) {
            Spacer()

            if let fraction = model.serviceProgress?.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 44)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 44)
            }

            if let progress = model.serviceProgress {
                Text(progress.stage.title)
                    .font(theme.headline(.title3))

                if let source = progress.source, !source.isEmpty {
                    // A publisher's own name.
                    Text(verbatim: source)
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if progress.total > 0 {
                    Text("\(progress.done) of \(progress.total)")
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(
                model.importRunsInBackground
                    ? "You can leave Flong. The import carries on and finishes on its own."
                    : "Keep Flong open until this is done. It picks up where it stopped if you have to leave."
            )
            .font(theme.metadata)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
    }
}
