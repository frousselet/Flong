//
//  SubscribedSitesScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The sites a reader pays for, and the sessions that prove it.
///
/// A feed is public and its articles are behind a wall : the reader subscribes,
/// signs in here on the site's own page, and Flong fetches the rest of an
/// article as them rather than as anybody.
///
/// **The screen is honest about what this costs.** A session is not a
/// credential : it is a thing a site can end whenever it likes, and it will.
/// Each row says when it was signed in and when it last worked, so a session
/// that has quietly stopped being recognized is visible rather than showing up
/// as articles that mysteriously went back to being teasers.
struct SubscribedSitesScreen: View {
    let model: AppModel

    @State private var isAdding = false
    @State private var host = ""
    @State private var signingInTo: SigningIn?

    var body: some View {
        List {
            Section {
                ForEach(model.subscribedSites, id: \.host) { site in
                    row(site)
                }
            } header: {
                Text("Sites")
            } footer: {
                Text(
                    "Sign in on the site's own page. Flong keeps the session in the keychain, never a password, and uses it only to fetch the articles of that site."
                )
            }
        }
        .navigationTitle(Text("Subscribed sites"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    host = ""
                    isAdding = true
                } label: {
                    Label("Add a site", systemImage: "plus")
                }
            }
        }
        .alert("Add a site", isPresented: $isAdding) {
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
        .overlay {
            if model.subscribedSites.isEmpty {
                ContentUnavailableView {
                    Label("No subscribed sites", systemImage: "key")
                } description: {
                    Text("Sign in to a site you pay for, and Flong will fetch its articles whole.")
                }
            }
        }
        .task { await model.loadSubscribedSites() }
    }

    private func row(_ site: SiteSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: site.host)

            // What a session is worth is when it last worked, not when it was
            // made : one signed in months ago and working yesterday is fine, and
            // one signed in yesterday that has never worked is not.
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
