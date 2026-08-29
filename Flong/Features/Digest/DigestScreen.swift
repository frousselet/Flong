//
//  DigestScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The front page.
///
/// One column, held to a readable measure whatever the window does, with the
/// stories set as an editor would set them : a rule, a headline, a line, and the
/// facts underneath. No cards, no boxes, no glass. Boxes are what an interface
/// reaches for when it does not trust its own typography, and they turn a page
/// into a control panel.
struct DigestScreen: View {
    let model: AppModel
    let zoom: Namespace.ID
    let open: (Route) -> Void

    /// Carries the rule from one period to the next.
    @Namespace private var rule

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                periods
                stories
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Digest"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
        }
        .refreshable { await model.refreshAll() }
        .overlay {
            if model.digest.isEmpty {
                ContentUnavailableView {
                    Label("Nothing has come in yet", systemImage: "sparkles.rectangle.stack")
                } description: {
                    Text("Flong groups your articles into stories as they arrive.")
                } actions: {
                    Button("Group now") { Task { await model.rebuildDigest() } }
                }
            }
        }
        .task { await model.loadLooseArticles() }
    }

    // MARK: - The page

    @ViewBuilder
    private var stories: some View {
        if !model.digest.live.isEmpty {
            header {
                HStack(spacing: 7) {
                    LiveDot()
                    Text("Happening now")
                }
            }
            ForEach(model.digest.live) { story in
                row(story)
            }
        }

        if !model.digest.stories.isEmpty {
            header { Text(Self.title(for: model.digestPeriod)) }
            ForEach(model.digest.stories) { story in
                row(story)
            }
        }

        if model.digest.looseCount > 0 {
            header { Text("The rest") }
            ForEach(model.looseArticles.prefix(40)) { article in
                ArticleRow(article: article, zoom: zoom) { open(.article(article.id)) }
            }
        }
    }

    private func header(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, Editorial.tightRhythm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ story: DigestStory) -> some View {
        StoryRow(story: story, zoom: zoom) { open(.story(story.id)) }
    }

    /// The period sits in the page rather than in the toolbar, and is set in
    /// type rather than drawn as a control.
    ///
    /// On iPad the tab bar already floats at the top, and a second capsule of
    /// glass under it is the stacking Apple's guidance warns against. A
    /// segmented control would be worse : a grey slab across the measure,
    /// speaking a different language from everything below it. Three words in
    /// the same kerned uppercase as the section headers, with a rule that slides
    /// under the one in force, say exactly as much and belong to the page.
    private var periods: some View {
        HStack(spacing: 20) {
            ForEach(DigestPeriod.allCases) { period in
                let isCurrent = model.digestPeriod == period
                Button {
                    withAnimation(.snappy(duration: 0.26)) { model.digestPeriod = period }
                } label: {
                    Text(Self.name(of: period))
                        .font(.system(.footnote, weight: isCurrent ? .semibold : .regular))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            if isCurrent {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "period", in: rule)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(.top, 6)
    }

    private static func name(of period: DigestPeriod) -> LocalizedStringResource {
        switch period {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    private static func title(for period: DigestPeriod) -> LocalizedStringResource {
        switch period {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        }
    }
}

/// One story, set as an editor would set it.
struct StoryRow: View {
    let story: DigestStory
    let zoom: Namespace.ID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: story.title)
                    .font(Editorial.headline(.title3))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = story.summary, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(Editorial.standfirst)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                facts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: story.id, in: zoom)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    /// Why this is here : who is saying it, how many of them, and how fast.
    ///
    /// It is the explanation the 2026 trend towards visible reasoning asks for,
    /// and it happens to be the only interesting thing about a story anyway.
    private var facts: some View {
        HStack(spacing: 10) {
            Text("\(story.feedCount) rooms")
            Text(verbatim: "·")
            Text("\(story.articleCount) articles")

            Sparkline(values: story.arrivals)
                .frame(width: 36, height: 9)

            Spacer(minLength: 4)

            if story.isGenerated {
                Image(systemName: "sparkles")
                    .accessibilityLabel(Text("Written by the model"))
                    .help(Text("Written by the model"))
            }
            Text(story.lastAt, format: .relative(presentation: .numeric))
                .lineLimit(1)
        }
        .font(Editorial.metadata)
        .foregroundStyle(.tertiary)
    }
}

/// One article, in a list of articles.
struct ArticleRow: View {
    let article: ArticleSummary
    let zoom: Namespace.ID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(article.isRead ? Color.clear : Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: article.title)
                        .font(Editorial.headline(.body))
                        .fontWeight(article.isRead ? .regular : .semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let excerpt = article.excerpt, !excerpt.isEmpty {
                        Text(verbatim: excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 8) {
                        Text(verbatim: article.feedTitle)
                            .lineLimit(1)
                        Text(article.date, format: .relative(presentation: .numeric))
                            .lineLimit(1)
                        if article.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel(Text("Starred"))
                        }
                        if article.hasMedia {
                            Image(systemName: "play.circle")
                                .accessibilityLabel(Text("Holds media"))
                        }
                    }
                    .font(Editorial.metadata)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: article.id, in: zoom)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        // The dot says unread by colour and shape alone, which says nothing at
        // all to a reader who is listening to the page.
        .accessibilityLabel(
            article.isRead ? Text("\(article.title), read") : Text("\(article.title), unread")
        )
    }
}
