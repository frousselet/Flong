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
                    ArticleRow(article: article, zoom: zoom) {
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
            Text("\(story.feedCount) rooms")
            Text(verbatim: "·")
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

    var body: some View {
        Group {
            if let article = model.article, article.id == articleID {
                ArticleWebView(html: ArticleDocument.html(for: article))
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar { toolbar(for: article) }
                    .navigationTitle(Text(verbatim: article.feedTitle))
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else {
                ProgressView()
            }
        }
        .task { await model.open(article: articleID) }
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
