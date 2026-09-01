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

/// Changing what a source is : its name, where it is served, whether that
/// address is a secret, which of its parameters are the reader's, and how it is
/// asked for.
///
/// **The address is why this screen exists.** A publisher who moves their feed,
/// a paper that goes to `https`, a blog that reorganizes its paths : until now
/// the only repair was to stop following the source and follow it again, which
/// takes the articles with it, and the stars, the notes and the filings on
/// them, on every device the reader owns. Editing the address moves the row and
/// leaves every one of those where it is.
///
/// **Whether an address is a secret is a fact about the address**, not a
/// setting beside it, so it is a switch in the same section and moving it moves
/// the source. A reader who pasted a per-subscriber address without saying it
/// was one had no way back : the address sat in the database and in their
/// iCloud, and the only repair was to unsubscribe. Turning the switch on masks
/// the row, puts the address in the keychain and takes the plain one out of
/// their iCloud with the record it was in. Turning it off writes it back in the
/// open, which the screen says before it is asked for.
///
/// **The parameters are here rather than behind a door.** They were a screen of
/// their own, reached from a second line of the same menu, which is one place
/// too many for something that is plainly a property of this source : the
/// question they ask is about these addresses, and this is where the addresses
/// are. What each one holds is shown masked, since the whole reason for asking
/// is that some of them are secrets.
///
/// **A name is the reader's, and it stays theirs.** A feed states a title and
/// Flong takes it while nothing better is known ; the moment the reader writes
/// one, that is the name, and no refresh and no re-import overwrites it.
///
/// **The site is not decoration.** It is what decides which publisher a source
/// files under and where its icon is looked for, so a feed served from a
/// syndication host with no site of its own sits under that host until somebody
/// says whose it is. That somebody can only be the reader.
struct SourceEditor: View {
    let model: AppModel
    /// The source as it stands, carried in rather than read again : a sheet
    /// that opened on nothing while it waited is a sheet that flickers.
    let feed: Feed

    @State private var name: String
    @State private var address: String
    @State private var site: String
    @State private var isSecret: Bool
    @State private var interval: TimeInterval?
    @State private var isFavourite: Bool

    /// The parameters this feed's addresses carry, and the ones the reader has
    /// said are theirs. The designations are folded, as the keychain holds
    /// them, so that `Token` and `token` are one answer.
    @State private var parameters: [AddressParameter] = []
    @State private var designated: Set<String> = []

    /// Why the edit was refused, said here rather than behind the sheet.
    ///
    /// An alert belonging to the window cannot be read over a sheet, and a
    /// refusal the reader has to close the screen to find is a refusal that
    /// takes their typing with it.
    @State private var refusal: AppFailure?
    @State private var isWorking = false

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
        let masked = MaskedURL.isMasked(feed.url)
        _name = State(initialValue: feed.title)
        // A masked address holds a digest of the real one and nothing a reader
        // would recognize, so the field starts empty rather than showing it.
        _address = State(initialValue: masked ? "" : feed.url.absoluteString)
        _isSecret = State(initialValue: masked)
        _site = State(initialValue: feed.siteURL?.absoluteString ?? "")
        _interval = State(initialValue: feed.refreshInterval)
        _isFavourite = State(initialValue: feed.isFavourite)
    }

    /// Whether the address stored for this source is the masked one, which is
    /// what the screen may not print. It is not the switch : the switch is what
    /// the reader is asking for, and this is what is.
    private var isKeptSecret: Bool { MaskedURL.isMasked(feed.url) }

    var body: some View {
        NavigationStack {
            Form {
                naming
                addressing
                belonging
                designating
                asking
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
            .task {
                parameters = await model.addressParameters(of: feed.id, feedURL: feed.url)
                designated = await model.secretParameters(of: feed.id)
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 540)
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
            // The address first, since it is what the switch under it is about.
            // Empty and secret is the ordinary state of a source whose address
            // is already one : there is nothing to show and nothing to type.
            TextField(text: $address) {
                if isKeptSecret {
                    Text("New secret address")
                } else {
                    Text("Address of the feed")
                }
            }
            .disabled(isWorking)
            .addressField()

            Toggle(isOn: $isSecret) {
                Text("This address is a secret")
            }
            .disabled(isWorking)

            if let refusal {
                Text(refusal.message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Address")
        } footer: {
            addressExplanation
        }
    }

    /// What the address section is about to do, which depends on where the
    /// switch is and where it was.
    @ViewBuilder
    private var addressExplanation: some View {
        if isSecret && isKeptSecret {
            Text(
                "The address is the secret, so it is never shown. Type a new one to replace it in the keychain, and the source keeps everything already here."
            )
        } else if isSecret {
            Text(
                "A subscription platform gives each subscriber an address nobody else has. It goes to the keychain, and out of the database and your iCloud, where it is sitting now."
            )
        } else if isKeptSecret {
            Text(
                "Turning this off writes the address back into the database and into your iCloud, in the open. Flong uses the one in the keychain unless you type another."
            )
        } else {
            Text(
                "A source that moves keeps its articles, everything you marked on them and the collections they are filed into. It is asked again at once, and your other devices follow."
            )
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

    /// Which parameters of this feed's addresses carry the subscription.
    ///
    /// **The reader says, because Flong cannot tell.** A platform that hands out
    /// a per-subscriber feed puts the subscriber in the query string, and so
    /// does a site that lets a reader pick a section : `?token=` and
    /// `?format=rss` look exactly alike from here. A heuristic that stripped
    /// them to be safe would hand somebody a link to the wrong page.
    ///
    /// The question is asked against real addresses, the feed's own and its
    /// articles', which is the only form in which it can be answered.
    @ViewBuilder
    private var designating: some View {
        Section {
            if parameters.isEmpty {
                ContentUnavailableView {
                    Label("No parameters", systemImage: "link")
                } description: {
                    Text("Neither this feed's address nor its articles carry any.")
                }
            } else {
                ForEach(parameters) { parameter in
                    Toggle(isOn: designation(of: parameter)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: parameter.name)
                            Text(verbatim: parameter.masked)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .disabled(isWorking)
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

    private var asking: some View {
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

    /// Whether one parameter is the reader's, compared as the keychain holds
    /// it : a designation is folded, and `Token` and `token` are one answer.
    private func designation(of parameter: AddressParameter) -> Binding<Bool> {
        Binding(
            get: { SecretParameters.folded(parameter.name).map(designated.contains) ?? false },
            set: { isSecret in
                guard let folded = SecretParameters.folded(parameter.name) else { return }
                if isSecret {
                    designated.insert(folded)
                } else {
                    designated.remove(folded)
                }
            }
        )
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
            siteAddress: site,
            refreshInterval: interval,
            isFavourite: isFavourite
        )
        let address: SourceAddress = isSecret ? .secret(self.address) : .open(self.address)
        let designated = designated

        Task {
            model.failure = nil
            await model.setSecretParameters(designated, for: feed.id)
            await model.editSource(feed.id, to: edit, address: address)
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
