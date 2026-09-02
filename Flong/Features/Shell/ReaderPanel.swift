//
//  ReaderPanel.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

#if os(iOS)
    import PhotosUI
#else
    import UniformTypeIdentifiers
#endif

/// The reader's own panel : who they are, and what only they can answer.
///
/// **There is no account here and this is not one.** Section 3 says there is no
/// server and nothing to sign in to, and a name typed into a feed reader is not
/// an exception to that : the name and the picture are the reader's own, kept
/// in the reader's own iCloud beside their other preferences, and there is
/// nowhere for them to be sent. What they buy is that a device the reader picks
/// up looks like theirs, which is the whole of it.
///
/// **It was a menu, and a menu was the wrong shape.** The face in the corner
/// opened a list of lines leading to screens : a profile, the sites, a command.
/// Two of those are things a reader sets and comes straight back from, and the
/// third was a command in a list of places. It is the fourth panel now, built
/// like the three in the other corner : closed by a flick, over the page rather
/// than in front of it. Untitled, where those three are not, for the reason the
/// head below sets out.
///
/// It holds what belongs to the person rather than to the page. The sites they
/// pay for, since being signed in to `lemonde.fr` is a fact about them and not
/// about any feed, and, where a build allows it, the command that makes the
/// exchange with iCloud happen on demand.
///
/// And, at the foot of it, the one command that takes something away for good.
/// A reader has no account to close, so deleting everything is what stands in
/// for closing one, and it belongs under their own face for the same reason the
/// name and the picture do.
///
/// Everything in it is optional and nothing is asked for twice. A reader who
/// never opens it gets a generic face and an application that works exactly as
/// well.
struct ReaderPanel: View {
    @Bindable var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var isNotAnImage = false
    @State private var isAddingSite = false
    @State private var isChoosingPlace = false
    @State private var host = ""
    @State private var signingInTo: SigningIn?
    @State private var isAskingToDeleteEverything = false
    @State private var sponsoringCode = ""
    @State private var trustingCode = ""
    @State private var banningCode = ""
    @State private var isDeletingEverything = false

    #if os(iOS)
        @State private var chosen: PhotosPickerItem?
    #else
        @State private var isChoosingFile = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head

            Form {
                face
                name
                whereabouts
                appearance
                sharing
                if model.isSponsoredIntoPool { sponsoring }
                if model.mayDecideForThePool { deciding }
                sites

                #if DEBUG
                    development
                #endif

                dangerZone
            }
            .scrollContentBackground(.hidden)
            .themedRows()
            #if os(macOS)
                .formStyle(.grouped)
            #endif
        }
        .presentationDetents([.height(Panel.tall), .large])
        .presentationDragIndicator(.visible)
        .alert(Text("That file is not an image"), isPresented: $isNotAnImage) {
            Button("OK", role: .cancel) {}
        }
        .alert("Add a site", isPresented: $isAddingSite) {
            // Verbatim : an example address is the same address in every
            // language, and the catalogue is for what a reader reads.
            TextField(text: $host) { Text(verbatim: "example.com") }
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
            Button("Sign in") { signingInTo = AppModel.site(of: host).map(SigningIn.init) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The address of a site you subscribe to, such as lemonde.fr.")
        }
        .alert("Delete everything?", isPresented: $isAskingToDeleteEverything) {
            Button("Delete everything", role: .destructive) {
                Task {
                    isDeletingEverything = true
                    await model.deleteEverything()
                    isDeletingEverything = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your subscriptions, every article, everything you kept and every site you are signed in to, on this device and in your iCloud. This cannot be undone. Another device that still has them will put its own copy back."
            )
        }
        .sheet(isPresented: $isChoosingPlace) {
            PlacePicker(model: model)
        }
        .sheet(item: $signingInTo) { signing in
            SiteLoginView(host: signing.host) { cookies in
                await model.saveSession(for: signing.host, cookies: cookies)
            }
        }
        .task { await model.loadSubscribedSites() }
        .themed()
    }

    /// The way out on the platform that needs one, and nothing else.
    ///
    /// **No title, where the three in the other corner have one.** They are
    /// places a reader went to on purpose and a word says which of the three
    /// arrived over the page. This one opens on the reader's own face at
    /// ninety-six points : nothing a title could say about who it is about
    /// would say it better.
    @ViewBuilder
    private var head: some View {
        #if os(macOS)
            HStack {
                Spacer(minLength: 0)
                PanelDismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        #endif
    }

    // MARK: - Who they are

    private var face: some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                ReaderMark(model: model, side: 96)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            picker

            if model.picture != nil {
                Button(role: .destructive) {
                    model.setPicture(nil)
                } label: {
                    Text("Remove the picture")
                }
            }
        }
    }

    private var name: some View {
        Section {
            TextField("First name", text: $model.firstName)
            TextField("Last name", text: $model.lastName)
        } header: {
            Text("Your name")
        } footer: {
            Text("Kept on your own devices, through your iCloud. Flong has no account and nowhere to send them.")
        }
    }

    /// Where the reader reads from, which is a fact about them like their name.
    ///
    /// **A town and a country, and never a street or a coordinate.** It sits
    /// under the reader's own face because it belongs to the person rather than
    /// to any page, and it is as coarse as it is because the question is which
    /// region somebody reads from. ``Place`` records why nothing finer is kept.
    ///
    /// **One row that opens the picker, rather than two fields.** A town typed
    /// by hand is a spelling, and two readers who both live in Lyon would
    /// spell it two ways ; what the picker gives back is a place MapKit
    /// recognizes, with the country code that goes with it. The row shows what
    /// was chosen, and taking it back is a line of its own so that it is never
    /// done by pressing the same row twice.
    private var whereabouts: some View {
        Section {
            Button {
                isChoosingPlace = true
            } label: {
                HStack(spacing: 12) {
                    // The name of the row is what has to stay whole : a long
                    // town truncates, and a label that gave up half of itself
                    // to one would leave the row saying nothing at all.
                    Text("City and country")
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Group {
                        if let place = model.place {
                            // Verbatim : a place name is a proper noun, and the
                            // catalogue is for what Flong says rather than for
                            // what MapKit named a town.
                            Text(verbatim: place.line)
                        } else {
                            Text("Not set")
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    Image(systemName: "chevron.forward")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if model.place != nil {
                Button(role: .destructive) {
                    model.setPlace(nil)
                } label: {
                    Text("Remove where you are")
                }
            }
        } header: {
            Text("Where you are")
        } footer: {
            Text("Kept beside your name, in your own iCloud. Flong has nowhere to send it.")
        }
    }

    /// Where a picture comes from, which is not the same place on each platform.
    ///
    /// A face on a phone is in the photo library, and the picker Apple provides
    /// runs outside the application, so nothing here ever sees the library
    /// itself and no permission is asked for. A face on a Mac is a file, and a
    /// Mac reader offered a photo library instead of the open panel would be
    /// offered the wrong drawer.
    @ViewBuilder
    private var picker: some View {
        #if os(iOS)
            PhotosPicker(selection: $chosen, matching: .images, photoLibrary: .shared()) {
                Text("Choose a picture")
            }
            .onChange(of: chosen) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    take(data)
                    chosen = nil
                }
            }
        #else
            Button("Choose a picture") { isChoosingFile = true }
                .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    // The panel hands back a file this application has no other
                    // right to read, and the right lasts exactly as long as it
                    // is held.
                    let opened = url.startAccessingSecurityScopedResource()
                    defer { if opened { url.stopAccessingSecurityScopedResource() } }
                    take(try? Data(contentsOf: url))
                }
        #endif
    }

    private func take(_ data: Data?) {
        guard let data, model.setPicture(data) else {
            isNotAnImage = true
            return
        }
    }

    // MARK: - How the application is set

    /// The three answers to what a page is.
    ///
    /// **It is in this panel because a theme is about the reader.** Everything
    /// under this face is what belongs to the person rather than to the page,
    /// and which face they want to read in is exactly that : it follows them to
    /// their next device, like their name and like the body an article opens
    /// on, and it says nothing about any feed they follow.
    ///
    /// **Each name is set in its own theme's headline face.** A list of three
    /// words in one face is a list that asks the reader to remember what
    /// `Solarized` looked like ; a list where each word is drawn in the face it
    /// will give them is a specimen, and choosing from a specimen takes no
    /// memory at all. The line under each says what the colours do, which is
    /// the half a specimen cannot show inside one row.
    private var appearance: some View {
        Section {
            Picker(selection: $model.theme) {
                ForEach(Theme.allCases) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .font(candidate.headline(.body))
                        Text(candidate.explanation)
                            .font(candidate.metadata)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(candidate)
                }
            } label: {
                Text("Theme")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Appearance")
        } footer: {
            Text("Carried to your other devices, like everything else you choose here.")
        }
    }

    // MARK: - What they offer the other readers

    /// Whether the reader offers what they follow to everybody else.
    ///
    /// **The one switch in this panel that sends something outside the
    /// reader's own account.** Everything else here is theirs and stays theirs
    /// : a name, a face, a town, a theme. This publishes a list of addresses
    /// into the database every copy of Flong reads, so what it publishes and
    /// what it never publishes are both written under it rather than left for
    /// the reader to guess.
    ///
    /// **Their identity in the pool is shown, and is meant to be handed over.**
    /// It is opaque, it says nothing about them, and it is the only thing a
    /// roster can name : a reader asking to be believed on their own has to be
    /// able to say who they are, and this is the whole of how.
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
        } header: {
            Text("Popular feeds")
        } footer: {
            if model.contributesToPool == true, !model.isSponsoredIntoPool {
                Text(
                    "Only readers somebody has brought in can add to the list. Give your code to a reader who is already in. Nothing of yours is published until then."
                )
            } else {
                Text(
                    "Only the addresses of the sources you follow. Not your name, not an article, not a word you wrote. A secret address is never shared, nor a source behind a password. Turn this off and your list is taken back out."
                )
            }
        }
    }

    /// Who this reader brought into the pool.
    ///
    /// **Shown to everybody who is in, and not only to the author.** The pool
    /// grows by sponsorship rather than by one person handing out every
    /// invitation, so this is an ordinary section of an ordinary panel for
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
            Text(
                "They can add to the popular feeds, and bring in others themselves. If one of them is cut out, everybody they brought in goes too."
            )
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
                Text("What these readers follow is suggested straight away, without waiting for ten people.")
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
                Text(
                    "They can still read and use Flong. What they offer counts for nobody, and so does what everybody they brought in offers."
                )
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
                    Text(
                        "Never suggested, whoever follows them. Only a fingerprint of the address is published, so a private address stays private."
                    )
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

    // MARK: - The sites they pay for

    /// The sites a reader pays for, and the sessions that prove it.
    ///
    /// A feed is public and its articles are behind a wall : the reader
    /// subscribes, signs in here on the site's own page, and Flong fetches the
    /// rest of an article as them rather than as anybody.
    ///
    /// **It is honest about what this costs.** A session is not a credential :
    /// it is a thing a site can end whenever it likes, and it will. Each row
    /// says when it was signed in and when it last worked, so a session that
    /// has quietly stopped being recognized is visible rather than showing up
    /// as articles that mysteriously went back to being teasers.
    private var sites: some View {
        Section {
            ForEach(model.subscribedSites, id: \.host) { site in
                row(site)
            }

            Button {
                host = ""
                isAddingSite = true
            } label: {
                Label("Add a site", systemImage: "plus")
            }
        } header: {
            Text("Subscribed sites")
        } footer: {
            Text(
                "Sign in on the site's own page. Flong keeps the session in the keychain, never a password, and uses it only to fetch the articles of that site."
            )
        }
    }

    private func row(_ site: SiteSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: site.host)

            // What a session is worth is when it last worked, not when it was
            // made : one signed in months ago and working yesterday is fine,
            // and one signed in yesterday that has never worked is not.
            Group {
                if !site.isUsable() {
                    Label("Signed out by the site", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let worked = site.lastWorkedAt {
                    Text("Last worked \(worked, format: .relative(presentation: .named))")
                } else {
                    Text("Signed in \(site.signedInAt, format: .relative(presentation: .named))")
                }
            }
            .font(theme.metadata)
            .foregroundStyle(.secondary)
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await model.signOut(of: site.host) }
            } label: {
                Label("Sign out", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                signingInTo = SigningIn(host: site.host)
            } label: {
                Label("Sign in again", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                Task { await model.signOut(of: site.host) }
            } label: {
                Label("Sign out", systemImage: "trash")
            }
        }
    }

    // MARK: - Starting over

    /// The one command here that takes something away for good.
    ///
    /// **It is in this panel because it is about the reader.** Everything else
    /// under this face is what they chose ; this is them taking all of it back,
    /// which is the same conversation and belongs in the same place. It stands
    /// at the bottom, so nothing above it can be pressed by mistake for it.
    ///
    /// **A card of its own rather than another row in the form.** Every other
    /// section here is a setting, and a setting is a thing a reader changes
    /// their mind about freely ; this one is not, and a row that looks like its
    /// neighbours is a row that is pressed like its neighbours. So it leaves the
    /// grouped background entirely and stands on red glass, which is the one
    /// place in the application the material is used to say danger rather than
    /// to float over a page. `docs/technical/interface.md` records why the
    /// exception is allowed here and nowhere else.
    ///
    /// **It says what it will do before it does it, and it is honest about what
    /// it cannot do.** There is no server and no account : deleting the zone
    /// and the archive empties the reader's iCloud, and a second device that
    /// still holds the subscriptions will recreate the zone and put its copy
    /// back. Promising otherwise would be promising a reach Flong does not
    /// have.
    private var dangerZone: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    // The mark is the red thing in the heading and the words are
                    // not : a title in red on a red wash is a title read with
                    // effort, and this is the one heading in the application
                    // that has to be read.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Danger zone")
                }
                .font(.headline)

                Text(
                    "Deletes every subscription, every article and everything you kept, here and in your iCloud. Flong starts again as it was on its first day."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    isAskingToDeleteEverything = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Delete everything")
                        if isDeletingEverything {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(isDeletingEverything)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A wash and not a coat. Tinted at full strength the glass stops
            // being glass : it is a flat red block, nothing of the page shows
            // through it, and the solid red of the button it holds disappears
            // into it. A third of the colour leaves the material doing its own
            // work and leaves the one control in the card the strongest red on
            // screen, which is the right way round.
            .glassEffect(.regular.tint(.red.opacity(0.3)), in: .rect(cornerRadius: 26))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - What only a build being worked on has

    /// The exchange with iCloud, on demand.
    ///
    /// A development command, and only there. The engine decides when to send
    /// and when to fetch and is right far more often than a button would be :
    /// this is for watching an exchange happen on demand while something is
    /// being built. It forgets the change tokens, the tags the server gave each
    /// record and the archives already read, then sends and fetches the whole
    /// of the zone, which is the repair path and spends the record budget of
    /// section 7 in one go. That is why it does not ship.
    #if DEBUG
        private var development: some View {
            Section {
                Button {
                    Task { await model.forceSynchronization() }
                } label: {
                    Label("Force a synchronization", systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
        }
    #endif
}

/// The site a login sheet is open for.
///
/// A type of its own rather than a retroactive `Identifiable` on `String` : a
/// conformance added to somebody else's type is a conformance every other file
/// in the target inherits without asking for it.
private struct SigningIn: Identifiable, Hashable {
    let host: String
    var id: String { host }
}
