//
//  AboutScreen.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the application is, at the foot of the reader's own panel.
///
/// **The one page under that face that is not about the reader**, which is why
/// it stands alone in a card of its own rather than beside the theme and the
/// sites. It answers the two questions a reader has of a version they are
/// holding : what it is, and which build it is.
///
/// **The mark, then the name in the theme's own face.** An icon is what a
/// reader recognizes the application by, and it is the one drawing in the whole
/// interface that belongs to Flong rather than to a publisher ; the name under
/// it is set in the headline face the reader chose, which is the one place in
/// the interface a theme speaks about the application rather than about an
/// article. One mark in both appearances, as an application icon is everywhere
/// else : it is a plate with its own ground, not a glyph taking the page's.
///
/// **It is honest by being short.** Two sentences about what Flong does
/// without, since that is the part a reader cannot see from the outside, and
/// three links out : where the source is, what licence it carries, and the one
/// dependency there is. No credits and no news of the version : a changelog
/// belongs in a repository, and the repository is one press away.
struct AboutScreen: View {
    /// The way out of the panel this page is pushed inside.
    let close: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                wordmark
                claim
                links
                signature
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .editorialColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text("About"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
    }

    /// The mark, the name in the face the reader chose, and the build under it.
    private var wordmark: some View {
        VStack(spacing: 10) {
            Image(.appMark)
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                // The plate is the drawing : it says nothing to anybody who is
                // not looking at it, and the name is right underneath.
                .accessibilityHidden(true)

            // Verbatim : the application is called Flong in every language.
            Text(verbatim: "Flong")
                .font(theme.headline(.title))

            Text("Version \(Self.version)")
                .font(theme.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// What Flong is, said in what it does without.
    private var claim: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "A feed reader with no server, no account and nothing to sign in to. Every device collects the feeds itself and keeps them in a database of its own."
            )
            Text(
                "What you choose to keep travels between your own devices through your own iCloud. Nothing else leaves this one but the requests to the feeds themselves. No telemetry, no tracker, no third party."
            )
        }
        .font(theme.standfirst(.subheadline))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the rest of the answer is, which is never inside an application.
    private var links: some View {
        VStack(spacing: 0) {
            link(
                Text("Source code"),
                saying: Text(verbatim: "github.com/frousselet/Flong"),
                to: "https://github.com/frousselet/Flong"
            )
            Divider().padding(.leading, 16)
            link(
                Text("License"),
                saying: Text(verbatim: "Mozilla Public License 2.0"),
                to: "https://www.mozilla.org/MPL/2.0/"
            )
            Divider().padding(.leading, 16)
            link(
                Text(verbatim: "GRDB"),
                saying: Text("The one dependency, for SQLite"),
                to: "https://github.com/groue/GRDB.swift"
            )
        }
        .background(theme.surface(in: scheme), in: .rect(cornerRadius: 18))
    }

    /// One row that leaves the application, and says so with its mark.
    ///
    /// An arrow going out rather than a chevron going forward : a chevron
    /// promises another page of this panel, and what is behind these three is a
    /// browser.
    private func link(_ name: Text, saying: Text, to address: String) -> some View {
        Link(destination: URL(string: address)!) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    name
                    saying
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Who wrote it, which is a name and a year and is not translated.
    private var signature: some View {
        Text(verbatim: "© 2026 François Rousselet")
            .font(theme.metadata)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    /// What this build calls itself.
    ///
    /// Read from the bundle rather than written here : a version typed into a
    /// source file is a version that stops agreeing with the one the project
    /// stamps on the build the first time either of them moves.
    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short else { return build ?? "" }
        guard let build else { return short }
        return "\(short) (\(build))"
    }
}
