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
/// like the three in the other corner : untitled, closed by a flick, over the
/// page rather than in front of it.
///
/// It holds what belongs to the person rather than to the page. The sites they
/// pay for, since being signed in to `lemonde.fr` is a fact about them and not
/// about any feed, and, where a build allows it, the command that makes the
/// exchange with iCloud happen on demand.
///
/// Everything in it is optional and nothing is asked for twice. A reader who
/// never opens it gets a generic face and an application that works exactly as
/// well.
struct ReaderPanel: View {
    @Bindable var model: AppModel

    @State private var isNotAnImage = false
    @State private var isAddingSite = false
    @State private var host = ""
    @State private var signingInTo: SigningIn?

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
                sites

                #if DEBUG
                    development
                #endif
            }
            .scrollContentBackground(.hidden)
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
        .sheet(item: $signingInTo) { signing in
            SiteLoginView(host: signing.host) { cookies in
                await model.saveSession(for: signing.host, cookies: cookies)
            }
        }
        .task { await model.loadSubscribedSites() }
    }

    /// The way out on the platform that needs one, and nothing else.
    ///
    /// No title. The panel is named by the face that opened it, which is the
    /// reader's own : nothing on screen says who this is about better than
    /// their own picture at the top of it.
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
            .font(Editorial.metadata)
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
