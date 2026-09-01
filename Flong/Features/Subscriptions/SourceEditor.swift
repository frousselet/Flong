//
//  SourceEditor.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Changing what a source is : its name, where it is served, and how it is
/// asked for.
///
/// **The address is why this screen exists.** A publisher who moves their feed,
/// a paper that goes to `https`, a blog that reorganizes its paths : until now
/// the only repair was to stop following the source and follow it again, which
/// takes the articles with it, and the stars, the notes and the filings on
/// them, on every device the reader owns. Editing the address moves the row and
/// leaves every one of those where it is.
///
/// **A name is the reader's, and it stays theirs.** A feed states a title and
/// Flong takes it while nothing better is known ; the moment the reader writes
/// one, that is the name, and no refresh and no re-import overwrites it.
///
/// **The site is not decoration.** It is what decides which publisher a source
/// files under and where its icon is looked for, so a feed served from a
/// syndication host with no site of its own sits under that host until somebody
/// says whose it is. That somebody can only be the reader.
///
/// **The address of a secret feed is not shown, and cannot be.** What the
/// database holds for one is already the masked form of section 9, which gives
/// nothing back : the reader is offered a new secret address instead, which
/// goes to the keychain and takes the source with it.
struct SourceEditor: View {
    let model: AppModel
    /// The source as it stands, carried in rather than read again : a sheet
    /// that opened on nothing while it waited is a sheet that flickers.
    let feed: Feed

    @State private var name: String
    @State private var address: String
    @State private var site: String
    @State private var secretAddress = ""
    @State private var interval: TimeInterval?
    @State private var isFavourite: Bool

    /// Why the edit was refused, said here rather than behind the sheet.
    ///
    /// An alert belonging to the window cannot be read over a sheet, and a
    /// refusal the reader has to close the screen to find is a refusal that
    /// takes their typing with it.
    @State private var refusal: AppFailure?
    @State private var isWorking = false
    @State private var isAddressing = false

    @Environment(\.dismiss) private var dismiss

    /// The intervals a reader is offered, inside the bounds of section 8.
    ///
    /// A handful rather than a field of seconds. Nobody wants a feed asked
    /// every seventeen minutes, and a number typed by hand is a number that can
    /// be a burden on a publisher by a slip of the finger.
    private static let intervals: [TimeInterval] = [
        15 * 60, 30 * 60, 60 * 60, 3 * 60 * 60, 6 * 60 * 60, 12 * 60 * 60, 24 * 60 * 60,
    ]

    init(model: AppModel, feed: Feed) {
        self.model = model
        self.feed = feed
        _name = State(initialValue: feed.title)
        _address = State(initialValue: MaskedURL.isMasked(feed.url) ? "" : feed.url.absoluteString)
        _site = State(initialValue: feed.siteURL?.absoluteString ?? "")
        _interval = State(initialValue: feed.refreshInterval)
        _isFavourite = State(initialValue: feed.isFavourite)
    }

    /// Whether the address is itself the secret, which is the case this screen
    /// may not print.
    private var isSecret: Bool { MaskedURL.isMasked(feed.url) }

    var body: some View {
        NavigationStack {
            Form {
                naming
                addressing
                belonging
                parameters
                health
            }
            .formStyle(.grouped)
            .themedRows()
            .navigationTitle(Text("Edit the source"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isWorking)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .sheet(isPresented: $isAddressing) {
                AddressParametersView(model: model, feedID: feed.id, feedURL: feed.url)
                    .themed()
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private var naming: some View {
        Section {
            TextField(text: $name) {
                Text("Name")
            }
            .disabled(isWorking)
            .autocorrectionDisabled()
        } footer: {
            // The address is written out because it is what the name falls back
            // to, and an address is the same address in every language.
            Text(
                "Leave it empty to call it \(Subscription.fallbackTitle(for: feed.url)) again.",
                comment: "The host a feed is served from, such as feeds.example.com"
            )
        }
    }

    @ViewBuilder
    private var addressing: some View {
        Section {
            if isSecret {
                LabeledContent {
                    Text(verbatim: feed.url.host() ?? "")
                } label: {
                    Text("Secret address")
                }
                TextField(text: $secretAddress) {
                    Text("New secret address")
                }
                .disabled(isWorking)
                .addressField()
            } else {
                TextField(text: $address) {
                    Text("Address of the feed")
                }
                .disabled(isWorking)
                .addressField()
            }

            if let refusal {
                Text(refusal.message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Address")
        } footer: {
            if isSecret {
                Text(
                    "The address is the secret, so it is never shown. A new one goes to the keychain and takes the source with it, keeping everything already here."
                )
            } else {
                Text(
                    "A source that moves keeps its articles, everything you marked on them and the collections they are filed into. It is asked again at once, and your other devices follow."
                )
            }
        }
    }

    private var belonging: some View {
        Section {
            TextField(text: $site) {
                Text("Address of the site")
            }
            .disabled(isWorking)
            .addressField()
        } footer: {
            Text(
                "Which publisher it is grouped under, and where its icon is looked for. Leave it empty and it is grouped under the address of the feed itself."
            )
        }
    }

    private var parameters: some View {
        Section {
            Picker(selection: $interval) {
                Text("Automatic").tag(TimeInterval?.none)
                ForEach(Self.intervals, id: \.self) { seconds in
                    // Verbatim : Foundation has already written it in the
                    // reader's language, and the catalogue would translate it
                    // a second time.
                    Text(verbatim: Self.spelled(seconds))
                        .tag(TimeInterval?.some(seconds))
                }
            } label: {
                Text("How often")
            }
            .disabled(isWorking)

            Toggle(isOn: $isFavourite) {
                Text("Favourite source")
            }
            .disabled(isWorking)

            Button {
                isAddressing = true
            } label: {
                Label("Address parameters", systemImage: "link")
            }
            .disabled(isWorking)
        } header: {
            Text("Parameters")
        } footer: {
            if let observed = feed.observedInterval {
                Text(
                    "Automatic follows the rhythm the feed shows, which is about \(Self.spelled(observed)) between articles.",
                    comment: "A length of time, such as 3 hours"
                )
            } else {
                Text("Automatic follows the rhythm the feed shows, between a quarter of an hour and a day.")
            }
        }
    }

    /// What the fetching has come to, which section 8 asks to be surfaced here.
    ///
    /// The 304 rate is the one number that says whether a source is being asked
    /// politely : a server that answers `not modified` to almost everything is
    /// one that is being asked well.
    @ViewBuilder
    private var health: some View {
        Section {
            LabeledContent {
                if let last = feed.lastSuccessAt {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
            } label: {
                Text("Last answered")
            }

            if let rate = feed.notModifiedRate {
                LabeledContent {
                    Text(rate, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Text("Answered not modified")
                }
            }

            if feed.failureCount > 0 {
                LabeledContent {
                    Text(feed.failureCount, format: .number)
                } label: {
                    Text("Failures in a row")
                }
            }
        } header: {
            Text("Health")
        } footer: {
            if feed.quarantinedAt != nil {
                Text("Flong stopped asking after repeated failures. Saving an address puts it back in service.")
            }
        }
    }

    /// A length of time in the reader's own language.
    private static func spelled(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide))
    }

    private func save() {
        guard !isWorking else { return }
        isWorking = true
        refusal = nil

        let edit = SourceEdit(
            title: name,
            // A secret address is never sent as an address : it is masked
            // first, where the secret can go to the keychain on the way past.
            address: isSecret ? "" : address,
            siteAddress: site,
            refreshInterval: interval,
            isFavourite: isFavourite
        )
        let secret = isSecret ? secretAddress : nil

        Task {
            model.failure = nil
            await model.editSource(feed.id, to: edit, secretAddress: secret)
            isWorking = false

            // Said on this screen rather than by the window behind it, and
            // taken off the window so that it is not said twice.
            if let refused = model.failure {
                refusal = refused
                model.failure = nil
                return
            }
            dismiss()
        }
    }
}

extension View {
    /// A field somebody types an address into.
    fileprivate func addressField() -> some View {
        self
            #if os(iOS)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
    }
}
