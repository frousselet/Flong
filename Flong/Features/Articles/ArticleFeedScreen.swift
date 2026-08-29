//
//  ArticleFeedScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A plain list of articles : unread, a feed, a folder, the library.
///
/// The same column and the same rows as the front page. A view of the stream is
/// not a different kind of place, it is the same place with a narrower question.
struct ArticleFeedScreen: View {
    let model: AppModel
    let kind: SidebarItem.Kind
    /// What the screen is called, when the section it sits in calls it
    /// something other than the view it shows.
    var named: LocalizedStringResource?
    let open: (UUID) -> Void

    @Namespace private var zoom

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.day) { day in
                    header(day.day)

                    ForEach(day.articles) { article in
                        ArticleRow(article: article, zoom: zoom) { open(article.id) }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await model.toggleRead(article) }
                                } label: {
                                    Label(
                                        article.isRead ? "Mark as unread" : "Mark as read",
                                        systemImage: article.isRead ? "circle" : "checkmark.circle"
                                    )
                                }
                            }
                    }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.markAllRead() }
                } label: {
                    Label("Mark all as read", systemImage: "checkmark.circle")
                }
                .disabled(model.summaries.allSatisfy(\.isRead))
            }
        }
        .refreshable { await model.refreshAll() }
        .overlay {
            if model.summaries.isEmpty {
                empty
            }
        }
        .task {
            model.selection = kind
            await model.loadArticles()
        }
    }

    /// The articles of a day, in the order they came.
    ///
    /// A wire of everything is a long scroll, and a scroll with no landmarks
    /// is one a reader loses their place in. The day is the landmark, set like
    /// the section headers of the front page.
    private var days: [(day: Date, articles: [ArticleSummary])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var grouped: [Date: [ArticleSummary]] = [:]

        for article in model.summaries {
            let day = calendar.startOfDay(for: article.date)
            if grouped[day] == nil { order.append(day) }
            grouped[day, default: []].append(article)
        }
        return order.map { (day: $0, articles: grouped[$0] ?? []) }
    }

    private func header(_ day: Date) -> some View {
        Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, Editorial.tightRhythm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An empty wire and an empty queue are not the same news.
    @ViewBuilder
    private var empty: some View {
        if kind == .unread {
            ContentUnavailableView {
                Label("Nothing to read", systemImage: "checkmark.circle")
            } description: {
                Text("Everything here has been read.")
            }
        } else {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text("Articles appear as they arrive.")
            }
        }
    }

    private var title: Text {
        if let named { return Text(named) }

        return switch kind {
        case .digest: Text("Digest")
        case .unread: Text("Unread")
        case .today: Text("Today")
        case .library: Text("Library")
        case .starred: Text("Starred")
        case .all: Text("All articles")
        case .folder(let path): Text(verbatim: FolderPath.name(of: path))
        case .feed: Text(verbatim: model.title(of: kind) ?? "")
        }
    }
}
