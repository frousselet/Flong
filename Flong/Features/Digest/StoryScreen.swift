//
//  StoryScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One story, as a page of its own.
///
/// It answers three questions in order : what happened, who says so, and what
/// each of them wrote. The first two are the whole reason a digest exists ; the
/// third is the reading, and it is last.
struct StoryScreen: View {
    let model: AppModel
    let storyID: UUID
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    @State private var isExplaining = false

    private var story: DigestStory? {
        (model.digest.live + model.digest.stories).first { $0.id == storyID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let story {
                    header(story)
                }

                ForEach(model.storyArticles[storyID] ?? []) { article in
                    // The picture at the top of the page came from one of these
                    // articles, and showing it again two hundred points below is
                    // saying the same thing twice.
                    ArticleRow(
                        article: article,
                        showsImage: article.imageURL != story?.imageURL,
                        zoom: zoom
                    ) {
                        open(article.id)
                    }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Story"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.openStoryPage(storyID) }
    }

    private func header(_ story: DigestStory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if story.imageURL != nil {
                RemoteImage(url: story.imageURL, aspect: Editorial.bandAspect, corner: 10)
                    .padding(.bottom, 2)
            }

            if !story.topics.isEmpty {
                Text(verbatim: story.topics.joined(separator: " · "))
                    .font(.system(.caption, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }

            Text(verbatim: story.title)
                .font(Editorial.headline(.largeTitle))
                .fixedSize(horizontal: false, vertical: true)

            if let summary = story.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if story.isGenerated {
                explanation
            }

            facts(story)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, Editorial.rhythm)
    }

    /// What the model did, said plainly, with the way back.
    ///
    /// The trend the research names is an assistant that is present, optional
    /// and explainable rather than an oracle. A reader who does not want a
    /// written headline gets the article's own, in one tap, and the application
    /// does not argue.
    private var explanation: some View {
        Button {
            isExplaining = true
        } label: {
            Label("Written by the model", systemImage: "sparkles")
                .font(Editorial.metadata)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "The headline and the line above were written on this device, from the articles below. Nothing was sent anywhere."
                )
                .font(.callout)

                Button("Use the article's own headline") {
                    isExplaining = false
                    Task { await model.dropGeneratedBrief(of: storyID) }
                }
            }
            .padding(16)
            .frame(maxWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func facts(_ story: DigestStory) -> some View {
        HStack(spacing: 10) {
            if story.isLive {
                LiveDot()
            }

            // The same marks the row carried, so the page a reader tapped
            // into opens on what they tapped.
            HStack(spacing: 3) {
                ForEach(story.feedMarks) { mark in
                    FeedIconView(stated: mark.iconURL, site: mark.siteURL, side: 15)
                }
                if story.feedCount > story.feedMarks.count {
                    Text(verbatim: "+\(story.feedCount - story.feedMarks.count)")
                        .padding(.leading, 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(story.feedCount) rooms"))

            Text("\(story.articleCount) articles")

            Sparkline(values: story.arrivals)
                .frame(width: 44, height: 10)

            Spacer(minLength: 4)
            Text(story.lastAt, format: .relative(presentation: .numeric))
        }
        .font(Editorial.metadata)
        .foregroundStyle(.tertiary)
    }
}

/// One article, read.
struct ArticleScreen: View {
    let model: AppModel
    let articleID: UUID

    /// Which body is being read.
    ///
    /// What the feed sent, which is what the publisher chose to send and is
    /// right far more often than a guess about somebody else's markup. The
    /// full article is one tap away, and asked for rather than assumed.
    @State private var showing = ArticleDocument.Body.feed
    /// Whether the page was asked for and had nothing to give, which is when
    /// signing in to the site is worth offering.
    @State private var pageGaveNothing = false
    @State private var signingIn = false

    var body: some View {
        Group {
            if let article = model.article, article.id == articleID {
                ArticleWebView(html: ArticleDocument.html(for: article, showing: showing))
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar { toolbar(for: article) }
                    .navigationTitle(Text(verbatim: article.feedTitle))
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .overlay(alignment: .bottom) {
                        if model.isFetchingFullText {
                            fetching
                        }
                    }
                    .sheet(isPresented: $signingIn) {
                        if let host = article.url.flatMap(FeedURL.room(of:)) {
                            SiteLoginView(host: host) { cookies in
                                await model.saveSession(for: host, cookies: cookies)
                                // Signed in : ask the page again, as them.
                                await showFullArticle()
                            }
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .task {
            showing = .feed
            pageGaveNothing = false
            await model.open(article: articleID)
        }
    }

    /// Said while the page is being fetched, and only then.
    ///
    /// The feed's version is on screen the whole time, so this is not a wait :
    /// it is the reason the text is about to get longer, which a reader would
    /// otherwise watch happen without explanation.
    /// Asks the page for the whole article, and shows it.
    ///
    /// On demand rather than on opening : the feed's version is what the reader
    /// sees by default, so fetching a page nobody has asked to see would be a
    /// request made to a publisher for something that is not going to be looked
    /// at. `docs/technical/extraction.md` is built on not doing that.
    private func showFullArticle() async {
        if model.article?.hasFullText != true {
            await model.fetchFullText()
        }

        if model.article?.hasFullText == true {
            showing = .page
            pageGaveNothing = false
        } else {
            pageGaveNothing = true
        }
    }

    private var fetching: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Fetching the full article")
        }
        .font(Editorial.metadata)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 24)
    }

    @ToolbarContentBuilder
    private func toolbar(for article: Article) -> some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await model.toggleStarredCurrent() }
            } label: {
                Label(
                    article.isStarred ? "Remove from favourites" : "Add to favourites",
                    systemImage: article.isStarred ? "star.fill" : "star"
                )
            }
        }

        if article.origin == .stream {
            ToolbarItem {
                Button {
                    Task { await model.markCurrentUnread() }
                } label: {
                    Label("Mark as unread", systemImage: "circle")
                }
            }
        }

        if article.url != nil {
            ToolbarItem {
                Menu {
                    if showing == .page {
                        Button {
                            showing = .feed
                        } label: {
                            Label("Show what the feed sent", systemImage: "doc.plaintext")
                        }
                    } else {
                        Button {
                            Task { await showFullArticle() }
                        } label: {
                            Label("Show the full article", systemImage: "doc.richtext")
                        }
                        .disabled(model.isFetchingFullText)
                    }

                    // Offered where the problem appears rather than four screens
                    // away : a page that gave nothing is usually a page that did
                    // not recognize the reader as a subscriber, and this is the
                    // moment they can do something about it.
                    if pageGaveNothing || model.hasSession(for: article.url) {
                        Divider()
                        Button {
                            signingIn = true
                        } label: {
                            Label(
                                model.hasSession(for: article.url) ? "Sign in again" : "Sign in to this site",
                                systemImage: "key"
                            )
                        }
                    }
                } label: {
                    Label("Article", systemImage: "doc.richtext")
                }
            }
        }

        if let url = article.url {
            ToolbarSpacer(.fixed)
            ToolbarItem {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem {
                Link(destination: url) {
                    Label("Open in browser", systemImage: "safari")
                }
            }
        }
    }
}
