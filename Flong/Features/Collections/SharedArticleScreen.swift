//
//  SharedArticleScreen.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// An excerpt somebody shared, read.
///
/// **In the reader and not in a browser.** A row used to leave the application
/// for the publisher's own page, on the argument that the article is not here.
/// It still is not, and that is a reason to fetch it rather than a reason to
/// hand the reader over to Safari : the machinery that turns a link into an
/// article is the one the rest of the application already uses, and a piece
/// somebody thought worth passing on is worth reading in the same type on the
/// same paper as everything else.
///
/// **Asked as the reader where the reader has signed in.** ``FullText`` carries
/// the session for the site, so a publisher they subscribe to serves them the
/// article rather than the teaser. Where the page gives nothing, signing in is
/// offered, exactly as it is on one of their own articles.
///
/// **Nothing is written down.** The article came from a feed this device does
/// not follow : it never enters `entry`, is never counted unread, never purged,
/// never indexed and never re-shared. What is on screen lives as long as the
/// reading and no longer.
struct SharedArticleScreen: View {
    let model: AppModel
    let entry: SharedEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    @State private var signingIn = false
    /// A page needs an article to have an identifier and this one has none of
    /// its own : made once for the reading, kept by nobody.
    @State private var identity = UUID.v7()

    /// The excerpt as an article the reader's own page builder understands.
    ///
    /// It is a value and not a row : nothing here is in the store and nothing
    /// here goes to it. The identifier is one nobody keeps, since a page needs
    /// one and this article has none of its own.
    private var article: Article {
        Article(
            id: identity,
            title: entry.title,
            feedTitle: entry.sourceTitle ?? "",
            // The publisher as everywhere else : worked out from the address
            // the article lives at, since a shared entry carries no feed of
            // this device's to look one up from.
            domain: FeedURL.publisher(
                site: entry.url.flatMap(URL.init(string:)),
                feed: entry.feedURL.flatMap(URL.init(string:))
            ),
            imageURL: entry.imageURL.flatMap(URL.init(string:)),
            author: entry.author,
            url: entry.url.flatMap(URL.init(string:)),
            publishedAt: entry.publishedAt,
            // The excerpt is plain text, so it is wrapped in a paragraph rather
            // than handed over as markup : nothing that crossed between two
            // accounts is ever treated as HTML.
            bodyHTML: Self.paragraph(entry.excerpt),
            extractedHTML: model.sharedArticleHTML
        )
    }

    var body: some View {
        NavigationStack {
            ArticlePage(
                html: ArticleDocument.html(
                    for: article,
                    publisher: entry.sourceTitle ?? article.domain,
                    showing: model.sharedArticleHTML == nil ? .feed : .page,
                    theme: theme
                )
            )
            .toolbar { toolbar }
            .overlay(alignment: .bottom) {
                if model.isFetchingSharedArticle { fetching }
            }
            .sheet(isPresented: $signingIn) {
                if let host = entry.url.flatMap(URL.init(string:)).flatMap(FeedURL.room(of:)) {
                    SiteLoginView(host: host) { cookies in
                        await model.saveSession(for: host, cookies: cookies)
                        // Signed in : ask the page again, as them.
                        await model.readSharedAgain(entry)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .tint(theme.accent(in: scheme))
            // No band across the top, for the reason ``ArticleScreen`` gives :
            // what is behind the controls is the paper the article is printed
            // on, and nothing else.
            #if os(iOS)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            #endif
        }
        .task { await model.readShared(entry) }
        .onDisappear { model.closeShared() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // A cross and not a way back : the page the reader came from never went
        // anywhere, and this is a thing put down.
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }

        ToolbarItem {
            Menu {
                // **Only where the page actually gave nothing.** A site that
                // served the article has no sign-in worth offering, and one
                // offered anyway would read as a wall that is not there.
                if model.sharedPageGaveNothing, entry.url != nil {
                    Button {
                        signingIn = true
                    } label: {
                        Label("Sign in to this site", systemImage: "person.badge.key")
                    }
                }

                if let address = entry.url.flatMap(URL.init(string:)) {
                    Button {
                        openURL(address)
                    } label: {
                        Label("Open on its own site", systemImage: "safari")
                    }
                    ShareLink(item: address) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis")
            }
        }
    }

    /// Said while the page is being asked for, and never in the way.
    ///
    /// The excerpt is already on screen and is worth reading meanwhile : this
    /// says the rest is coming rather than standing in front of it.
    private var fetching: some View {
        HStack(spacing: 8) {
            WaitingRing(side: 15)
            Text("Fetching the article")
                .font(theme.metadata)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: .capsule)
        .padding(.bottom, 24)
    }

    /// Plain text as one paragraph, escaped.
    ///
    /// The excerpt crossed from another person's device and is text by
    /// construction ; escaping it is the second lock, so that a sender who put
    /// markup where text was expected has written characters and not tags.
    private static func paragraph(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<p>" + escaped + "</p>"
    }
}
