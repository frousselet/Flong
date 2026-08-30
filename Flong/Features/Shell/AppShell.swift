//
//  AppShell.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers

/// Where the reader can be.
nonisolated enum Route: Hashable {
    case story(UUID)
    case article(UUID)
    case view(SidebarItem.Kind)
    case sources
    case profile
    case topics
    case subscribedSites
}

/// Which part of the application the reader is in.
///
/// Named `AppSection` rather than `Section`, which is a view SwiftUI already
/// has and which every screen here uses.
nonisolated enum AppSection: Hashable {
    case digest
    case stream
    case library
    case search
}

/// The whole window : one column at a time, under a bar that gets out of the
/// way.
///
/// Not three panes. A reader is reading one thing at a time, and two columns of
/// chrome around it are two columns of not reading. The tab bar is the system's,
/// which matters : it is the only Liquid Glass in the application, it minimizes
/// itself when the reader scrolls into an article, and it holds search where the
/// system puts search. A bar of my own next to it would be glass on glass, which
/// is the one thing Apple's guidance forbids outright.
struct AppShell: View {
    @State private var model: AppModel
    @State private var section = AppSection.digest
    @State private var digestPath: [Route] = []
    @State private var streamPath: [Route] = []
    @State private var libraryPath: [Route] = []
    @State private var searchPath: [Route] = []
    @State private var isAddingFeed = false
    @State private var isChoosingFile = false
    @Namespace private var zoom

    @Environment(\.scenePhase) private var scenePhase

    init(database: AppDatabase) {
        _model = State(initialValue: AppModel(database: database))
    }

    var body: some View {
        TabView(selection: $section) {
            Tab("Digest", systemImage: "sparkles.rectangle.stack", value: AppSection.digest) {
                stack($digestPath) {
                    DigestScreen(
                        model: model,
                        zoom: zoom,
                        isAddingFeed: $isAddingFeed,
                        isChoosingFile: $isChoosingFile
                    ) { digestPath.append($0) }
                }
            }

            // Everything, newest first : the wire, not a queue. A queue is a
            // thing to get to the end of, and a reader who is watching a
            // subject is not trying to finish anything. It carries no count
            // either, for the same reason : a number that only ever grows is a
            // debt, and nobody owes their feeds anything. Unread on its own is
            // still a view, in the sources list, for whoever does want it.
            //
            // Four sections and not five : the sources are not a place a reader
            // is, they are a thing a reader keeps, so they live in the menu with
            // the rest of what has been decided rather than in the bar beside
            // the places there are to read.
            Tab("Stream", systemImage: "dot.radiowaves.left.and.right", value: AppSection.stream) {
                stack($streamPath) {
                    ArticleFeedScreen(
                        model: model,
                        kind: .all,
                        named: "Stream",
                        showsArrivals: true,
                        menu: { streamPath.append($0) }
                    ) { streamPath.append(.article($0)) }
                }
            }

            Tab("Collections", systemImage: "bookmark", value: AppSection.library) {
                stack($libraryPath) {
                    ArticleFeedScreen(model: model, kind: .library, menu: { libraryPath.append($0) }) {
                        libraryPath.append(.article($0))
                    }
                }
            }

            Tab(value: AppSection.search, role: .search) {
                stack($searchPath) {
                    SearchScreen(model: model, zoom: zoom, menu: { searchPath.append($0) }) {
                        searchPath.append(.article($0))
                    }
                }
            }
        }
        // The bar gets out of the way when the reader scrolls into something.
        // On macOS there is no bar to minimize : the same sections become the
        // sidebar the system draws for an adaptable tab view, which is where a
        // Mac window keeps them, and a window is already out of its own way.
        #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
        #else
            .tabViewStyle(.sidebarAdaptable)
        #endif
        .sheet(isPresented: $isAddingFeed) {
            AddFeedView(
                add: { address in await model.addFeed(at: address) },
                addPrivate: { address in await model.addPrivateFeed(at: address) }
            )
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.opmlTypes) { result in
            guard case .success(let url) = result else { return }
            Task { await model.importOPML(from: url) }
        }
        .task {
            await model.load()
            await model.rebuildDigest()
            await model.startSync()
            await model.synchronizeSpotlight()
            await model.refreshDue()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshDue() }
        }
        .alert(
            Text("Import finished"),
            isPresented: Binding(get: { model.report != nil }, set: { if !$0 { model.report = nil } }),
            presenting: model.report
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(verbatim: Self.summary(of: report))
        }
        .alert(
            Text("Something went wrong"),
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
            presenting: model.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    /// One stack per section, so going back means going back where the reader
    /// was rather than to the beginning of everything.
    private func stack(_ path: Binding<[Route]>, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route, path: path)
                }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route, path: Binding<[Route]>) -> some View {
        switch route {
        case .story(let id):
            // The page grows out of the row that was tapped rather than sliding
            // in from nowhere : the motion says where it came from, which is the
            // only thing motion is for. macOS has no such transition and needs
            // none, a window being its own explanation.
            zoomed(
                StoryScreen(model: model, storyID: id, zoom: zoom) {
                    path.wrappedValue.append(.article($0))
                },
                from: id
            )

        case .article(let id):
            zoomed(ArticleScreen(model: model, articleID: id), from: id)

        case .view(let kind):
            ArticleFeedScreen(model: model, kind: kind) { path.wrappedValue.append(.article($0)) }

        case .sources:
            SourcesScreen(model: model, isAddingFeed: $isAddingFeed, isChoosingFile: $isChoosingFile) {
                path.wrappedValue.append(.view($0))
            }

        case .profile:
            ProfileScreen(model: model)

        case .topics:
            TopicsScreen(model: model)

        case .subscribedSites:
            SubscribedSitesScreen(model: model)
        }
    }

    @ViewBuilder
    private func zoomed(_ content: some View, from id: UUID) -> some View {
        #if os(macOS)
            content
        #else
            content.navigationTransition(.zoom(sourceID: id, in: zoom))
        #endif
    }

    private static var opmlTypes: [UTType] {
        [UTType(filenameExtension: "opml"), .xml].compactMap { $0 }
    }

    private static func summary(of report: OPMLImportReport) -> String {
        var lines = [String(localized: "\(report.added) feeds added")]
        if report.alreadyFollowed > 0 {
            lines.append(String(localized: "\(report.alreadyFollowed) already followed"))
        }
        if !report.skipped.isEmpty {
            lines.append(String(localized: "\(report.skipped.count) ignored"))
        }
        return lines.joined(separator: "\n")
    }
}
