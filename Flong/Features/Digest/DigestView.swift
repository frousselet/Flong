//
//  DigestView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The main screen : what is happening, not what arrived.
///
/// An aggregator shows articles newest first and leaves the reader to work out
/// what matters. This shows **stories** : several articles from several rooms
/// about one thing, with the ones still arriving at the top. The unit changes,
/// and everything else follows from that.
struct DigestView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                Picker(selection: Binding(get: { model.digestPeriod }, set: { model.digestPeriod = $0 })) {
                    Text("Day").tag(DigestPeriod.day)
                    Text("Week").tag(DigestPeriod.week)
                    Text("Month").tag(DigestPeriod.month)
                } label: {
                    Text("Digest")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if !model.digest.live.isEmpty {
                    section(header: liveHeader, stories: model.digest.live)
                }
                if !model.digest.stories.isEmpty {
                    section(
                        header: AnyView(header(Text(Self.title(for: model.digestPeriod)))),
                        stories: model.digest.stories)
                }
                if model.digest.looseCount > 0 {
                    loose
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text("Digest"))
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

    // MARK: - Sections

    private var liveHeader: AnyView {
        AnyView(
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Happening now")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.background)
        )
    }

    private func header(_ text: Text) -> some View {
        text
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.background)
    }

    private func section(header: AnyView, stories: [DigestStory]) -> some View {
        Section {
            ForEach(stories) { story in
                StoryCard(
                    story: story,
                    isOpen: model.openStory == story.id,
                    articles: model.storyArticles[story.id] ?? [],
                    selected: model.selectedArticle
                ) {
                    Task { await model.toggle(story) }
                } select: { article in
                    model.selectedArticle = article.id
                }
            }
        } header: {
            header
        }
    }

    private var loose: some View {
        Section {
            DisclosureGroup {
                ForEach(model.looseArticles) { article in
                    Button {
                        model.selectedArticle = article.id
                    } label: {
                        StoryArticleRow(article: article, isSelected: model.selectedArticle == article.id)
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                Text("\(model.digest.looseCount) articles made no story")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

/// One story, as a card.
private struct StoryCard: View {
    let story: DigestStory
    let isOpen: Bool
    let articles: [ArticleSummary]
    let selected: UUID?
    let toggle: () -> Void
    let select: (ArticleSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: story.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)

                    if let summary = story.summary, !summary.isEmpty {
                        Text(verbatim: summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }

                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(articles) { article in
                        Button {
                            select(article)
                        } label: {
                            StoryArticleRow(article: article, isSelected: selected == article.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: story.title))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: Self.sources(of: story))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                Sparkline(values: story.arrivals)
                    .frame(width: 40, height: 10)

                Text("\(story.articleCount) articles")
                Text(story.lastAt, format: .relative(presentation: .numeric))
                    .lineLimit(1)

                if story.isGenerated {
                    Image(systemName: "sparkles")
                        .accessibilityLabel(Text("Written by the model"))
                        .help(Text("Written by the model"))
                }
                Spacer(minLength: 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The rooms talking about it, and how many more there are.
    private static func sources(of story: DigestStory) -> String {
        let named = story.feedTitles.joined(separator: " · ")
        let rest = story.feedCount - story.feedTitles.count
        return rest > 0 ? "\(named) +\(rest)" : named
    }
}

/// One article inside a story.
private struct StoryArticleRow: View {
    let article: ArticleSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(article.isRead ? Color.clear : Color.accentColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: article.title)
                    .font(.subheadline)
                    .fontWeight(article.isRead ? .regular : .medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(verbatim: article.feedTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }
}

/// The shape of a story's arrival.
///
/// It is what tells a burst from a trickle at a glance, which is the one thing a
/// number cannot say.
private struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(values.max() ?? 1, 1)
            let width = geometry.size.width / CGFloat(max(values.count, 1))

            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .frame(
                            width: max(width - 1, 1),
                            height: max(geometry.size.height * CGFloat(value) / CGFloat(peak), 1)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
}
