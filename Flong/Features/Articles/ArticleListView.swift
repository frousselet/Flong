//
//  ArticleListView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The second level : which article.
struct ArticleListView: View {
    let model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.selectedArticle }, set: { model.selectedArticle = $0 })) {
            ForEach(model.summaries) { summary in
                ArticleRow(summary: summary)
                    .tag(summary.id)
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await model.toggleRead(summary) }
                        } label: {
                            Label(
                                summary.isRead ? "Mark as unread" : "Mark as read",
                                systemImage: summary.isRead ? "circle" : "checkmark.circle"
                            )
                        }
                        .tint(.accentColor)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await model.toggleStarred(summary) }
                        } label: {
                            Label(
                                summary.isStarred ? "Remove from favourites" : "Add to favourites",
                                systemImage: summary.isStarred ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
            }
        }
        .refreshable { await model.refreshAll() }
        .navigationTitle(Text("Articles"))
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.markAllRead() }
                } label: {
                    Label("Mark all as read", systemImage: "checkmark.circle")
                }
                .disabled(model.summaries.allSatisfy(\.isRead))
            }
            ToolbarItem {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
        }
        .overlay {
            if model.summaries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to read", systemImage: "checkmark.circle")
                } description: {
                    Text("Everything here has been read.")
                }
            }
        }
    }
}

/// One row of the list.
///
/// The excerpt is what makes a list worth scrolling, and the feed and the date
/// are what place an article without opening it.
private struct ArticleRow: View {
    let summary: ArticleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(summary.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: summary.title)
                    .font(.headline)
                    .fontWeight(summary.isRead ? .regular : .semibold)
                    .lineLimit(3)

                if let excerpt = summary.excerpt, !excerpt.isEmpty {
                    Text(verbatim: excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(verbatim: summary.feedTitle)
                        .lineLimit(1)
                    Text(summary.date, format: .relative(presentation: .named))
                    if summary.hasMedia {
                        Image(systemName: "play.circle")
                            .accessibilityLabel(Text("Holds media"))
                    }
                    if summary.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(Text("Starred"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            summary.isRead
                ? Text("\(summary.title), read")
                : Text("\(summary.title), unread")
        )
    }
}
