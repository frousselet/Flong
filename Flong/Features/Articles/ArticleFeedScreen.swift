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

/// A plain list of articles : unread, a feed, a publisher, everything.
///
/// The same column and the same rows as the front page. A view of the stream is
/// not a different kind of place, it is the same place with a narrower question.
struct ArticleFeedScreen: View {
    let model: AppModel
    let kind: SidebarItem.Kind
    /// What the screen is called, when the section it sits in calls it
    /// something other than the view it shows.
    var named: LocalizedStringResource?
    /// Whether the month's arrivals are drawn over the list.
    var showsArrivals = false
    /// Where the reader's menu goes, when this screen is one a section opens on.
    ///
    /// A pushed list is a feed, a publisher or a view of the stream, and it keeps
    /// the command that belongs to it, which is giving up on the lot. A section
    /// the reader lands in keeps the menu instead : one button, one corner, the
    /// same in all four.
    var menu: ((Route) -> Void)?
    let open: (UUID) -> Void

    @Namespace private var zoom

    /// The day the reader has scrolled to, which is what the chart is about.
    @State private var day: Date?
    /// The moment at the top of the list, which is the hour the chart marks.
    @State private var moment: Date?
    /// Whether anything has scrolled under the chart, which is what its glass
    /// is for. At rest there is nothing behind it and it wears none.
    @State private var isCovered = false

    /// The hour the chart has its mark on, which is what a reader feels turn
    /// over as they scroll.
    private var markedHour: Date? {
        moment.map { Hours.hour(of: $0) }
    }

    /// How far the page stands in from the edges of the screen.
    ///
    /// Named because the chart has to undo it : uncovered it runs the whole
    /// width, which means stepping back out of the column the rest of the page
    /// is set in.
    private static let gutter: CGFloat = 22

    var body: some View {
        let rows = self.rows

        return ScrollView {
            // A pinned section header, exactly as the front page pins its
            // subjects : the bar in the safe area lays itself out in the middle
            // of the screen here, and a header is where this one belongs
            // anyway, at the head of what it describes.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        if let article = row.article {
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
                        } else {
                            header(row.id.day)
                        }
                    }
                } header: {
                    arrivals(rows)
                }
            }
            .scrollTargetLayout()
            .editorialColumn()
            .padding(.horizontal, Self.gutter)
            .padding(.bottom, 90)
        }
        // Which day the reader is in, asked of the rows themselves. The list
        // runs newest first, so the newest day with a row still on screen is
        // the day at the top of it.
        .onScrollTargetVisibilityChange(idType: WireRow.Key.self) { visible in
            // The newest moment still on screen : the list runs newest first,
            // so that is what the reader has reached.
            if let top = visible.map(\.moment).max(), top != moment { moment = top }

            // The day is kept apart from it. It is what the haptic answers to,
            // and a buzz at every row rather than at every dateline would be a
            // buzz nobody asked for.
            guard let top = visible.map(\.day).max(), top != day else { return }
            day = top
        }
        // Whether the list has moved under the chart at all. Asked of the
        // offset rather than of the rows : a row is a landmark and this is a
        // question about a single point, the top of the content against the top
        // of what is shown.
        //
        // Against a hair rather than against nought : a scroll view rests at a
        // fractional offset often enough, and a glass that flickered on and off
        // while the reader held still would be worse than one that never left.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, covered in
            isCovered = covered
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The bar moving is felt as well as seen, and the bar is an hour now :
        // triggering on the day meant scrolling through a whole day of a busy
        // wire without feeling anything, which is the chart moving under the
        // reader in silence.
        //
        // Only once they have actually moved : the first hour the list settles
        // on is not a change, and a buzz on opening a screen is a buzz nobody
        // asked for.
        .sensoryFeedback(trigger: markedHour) { previous, current in
            showsArrivals && previous != nil && current != nil ? .selection : nil
        }
        // A large title, like the front page's dateline and the sources list :
        // it stands at the head of the page and shrinks into the bar as the
        // reader scrolls into it. An inline title is already shrunk and says
        // where you are without ever saying it was worth a line.
        .navigationTitle(title)
        .toolbar {
            if let menu {
                ToolbarItem(placement: .sectionLeading) {
                    SourcesButton(model: model, open: menu)
                }
                ToolbarItem(placement: .sectionLeading) {
                    TopicsButton(model: model)
                }
                ToolbarItem(placement: .sectionLeading) {
                    NotificationsButton(model: model)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let menu {
                    ReaderButton(model: model)
                } else {
                    Button {
                        Task { await model.markAllRead() }
                    } label: {
                        Label("Mark all as read", systemImage: "checkmark.circle")
                    }
                    .disabled(model.summaries.allSatisfy(\.isRead))
                }
            }
        }
        .overlay {
            if model.summaries.isEmpty {
                empty
            }
        }
        .task {
            model.selection = kind
            day = nil
            await model.loadArticles()
        }
    }

    // MARK: - The month over the list

    @ViewBuilder
    private func arrivals(_ rows: [WireRow]) -> some View {
        if showsArrivals, let newest = rows.first?.id.day, let oldest = rows.last?.id.day {
            ArrivalsChart(
                counts: model.hourlyCounts,
                days: Hours.spanning(oldest, to: newest),
                current: moment ?? day ?? newest,
                isCovered: isCovered
            )
            .padding(.vertical, 9)
            // Pinned is not the same as in front : without this the rows pass
            // over the bars rather than under them, and a headline crossing the
            // chart is drawn on top of it.
            .zIndex(1)
        }
    }

    // MARK: - The list

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

    /// The days and their articles as one flat list of rows.
    private var rows: [WireRow] {
        days.flatMap { day in
            [WireRow(id: WireRow.Key(day: day.day, moment: day.day, article: nil), article: nil)]
                + day.articles.map {
                    WireRow(id: WireRow.Key(day: day.day, moment: $0.date, article: $0.id), article: $0)
                }
        }
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
                Label("Nothing here yet", systemImage: "tray")
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
        case .starred: Text("Starred articles")
        case .all: Text("All articles")
        case .group(let domain): Text(verbatim: model.title(of: kind) ?? domain)
        case .feed: Text(verbatim: model.title(of: kind) ?? "")
        }
    }
}

/// One line of the wire : the dateline that opens a day, or an article under it.
///
/// Flat, rather than a group per day, and deliberately. A day of eighty
/// articles wrapped in a stack of its own is eighty rows built at once, and
/// eighty pictures asked for at once, the moment that day comes near the
/// screen : the enclosing stack is lazy and a stack inside it is not. A flat
/// list stays lazy, and the day rides along in each row's own identity, which
/// is how the chart above still knows which day is on screen.
private struct WireRow: Identifiable {
    struct Key: Hashable {
        let day: Date
        /// When the article arrived, which the chart marks to the hour. The
        /// day alone would put the mark on midnight of a day the reader is
        /// reading the evening of.
        let moment: Date
        /// Nothing at all, for the dateline that opens the day.
        let article: UUID?
    }

    let id: Key
    let article: ArticleSummary?
}
