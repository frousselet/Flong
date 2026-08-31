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
    case collection(ArticleCollection.Kind)
}

/// The article being read, when one is.
///
/// A type of its own so the presentation can be keyed on it. `UUID` would do as
/// well and would be a conformance added to somebody else's type, which every
/// other file in the target would then inherit without asking for it.
nonisolated struct Reading: Identifiable, Hashable {
    let id: UUID
}

/// Which part of the application the reader is in.
///
/// Named `AppSection` rather than `Section`, which is a view SwiftUI already
/// has and which every screen here uses.
nonisolated enum AppSection: Hashable {
    case digest
    case stream
    case collections
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
    @State private var collectionsPath: [Route] = []
    @State private var searchPath: [Route] = []
    /// The article being read, when one is.
    ///
    /// It used to be a route on whichever section's stack the reader was in,
    /// which drew an article under the tab bar. One thing is read at a time and
    /// it is read over everything, so it is presented rather than pushed, and
    /// it belongs to the window rather than to a section.
    @State private var reading: Reading?
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
                    let open: (Route) -> Void = opening($digestPath)

                    DigestScreen(
                        model: model,
                        zoom: zoom,
                        isAddingFeed: $isAddingFeed,
                        isChoosingFile: $isChoosingFile,
                        open: open
                    )
                }
            }

            // Everything, newest first : the wire, not a queue. A queue is a
            // thing to get to the end of, and a reader who is watching a
            // subject is not trying to finish anything. It carries no count
            // either, for the same reason : a number that only ever grows is a
            // debt, and nobody owes their feeds anything. Unread on its own is
            // still a view, in the sources list, for whoever does want it.
            //
            // A full tray, which is the mark the same view already wears in the
            // sources list, and which the bar can fill : every mark in the bar
            // has a filled variant and the bar reaches for it, so one that has
            // none is the one thing in the row drawn as a hairline.
            //
            // Four sections and not five : the sources are not a place a reader
            // is, they are a thing a reader keeps, so they live in the menu with
            // the rest of what has been decided rather than in the bar beside
            // the places there are to read.
            Tab("Stream", systemImage: "tray.full", value: AppSection.stream) {
                stack($streamPath) {
                    ArticleFeedScreen(
                        model: model,
                        kind: .all,
                        zoom: zoom,
                        named: "Stream",
                        showsArrivals: true,
                        menu: opening($streamPath)
                    ) { reading = Reading(id: $0) }
                }
            }

            Tab("Collections", systemImage: "folder", value: AppSection.collections) {
                stack($collectionsPath) {
                    CollectionsScreen(model: model, menu: opening($collectionsPath)) {
                        collectionsPath.append(.collection($0))
                    }
                }
            }

            Tab(value: AppSection.search, role: .search) {
                stack($searchPath) {
                    SearchScreen(model: model, zoom: zoom, menu: opening($searchPath)) {
                        reading = Reading(id: $0)
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
        // Who an article came from is asked by every row of every list, and it
        // is one answer per publisher rather than one per feed. Injected once,
        // here, so no screen has to carry it down to the row that draws it.
        .environment(\.publishers, model.publishers)
        // **The one thing that is read is read over everything.** Presented
        // from the window rather than pushed onto a section, so the tab bar is
        // behind it rather than drawn across it, and the page the reader came
        // from is still there when they put the article down.
        .sheet(item: $reading) { article in
            zoomed(ArticleScreen(model: model, articleID: article.id), from: article.id)
        }
        .sheet(isPresented: $isAddingFeed) {
            AddFeedView(
                add: { address in await model.addFeed(at: address) },
                addPrivate: { address in await model.addPrivateFeed(at: address) }
            )
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: OPMLDocument.types) { result in
            guard case .success(let url) = result else { return }
            Task { await model.importOPML(from: url) }
        }
        .task {
            // Before anything else that could take a while : a notification
            // tapped from a cold start has been waiting since before the
            // window existed, and the reader is looking at the wrong page
            // until it is claimed.
            NotificationRouter.shared.listen { story in
                section = .digest
                digestPath = [.story(story)]
            }

            // The background tasks were registered while the application
            // launched, before there was a window or a model to do the work.
            // This is where they are given one. Without it both tasks run and
            // call into nothing, which is what they had been doing.
            FlongApp.work.set(
                refresh: { @MainActor in await model.backgroundRefresh() },
                process: { @MainActor in await model.backgroundProcessing() }
            )
            BackgroundScheduler.schedule()
            // Asked for once per launch, and otherwise only by its own handler.
            // Asking for it again on every foreground return pushed it six
            // hours further out each time, so on a phone anyone actually uses
            // it never ran.
            BackgroundScheduler.scheduleFullPass()

            // A window that opens in the background has no phase change to
            // learn from, and `onChange` only fires on a change.
            model.isReading = scenePhase == .active

            // Before the page is read : the subjects a story is filed under are
            // chosen from this vocabulary, and a filing pass that ran before it
            // existed had nothing to choose from and stamped the story as asked
            // all the same.
            await model.seedStandardTopics()
            await model.load()

            // Follows the store and the clock from here on, so a change from
            // anywhere reaches the window without the reader asking for
            // anything. The clock's first turn is the launch refresh, so
            // nothing is asked for twice.
            model.keepUp()

            await model.startSync()
            await model.synchronizeSpotlight()
        }
        .onChange(of: scenePhase) { _, phase in
            // What the reader is looking at decides whether Flong may
            // interrupt them about something on that very page.
            model.isReading = phase == .active

            guard phase == .active else {
                // Asked for on the way out, which is when iOS wants it : a task
                // is submitted for an application that has stopped, and the
                // request is replaced rather than duplicated. The refresh only :
                // the full pass keeps its own clock.
                BackgroundScheduler.schedule()
                return
            }
            // A reader who has just switched Apple Intelligence on, or whose
            // assets have finished downloading, is a reader whose model is
            // worth asking again.
            OnDeviceModel.reconsider()
            // Asked again in case the observation could not be started : it is
            // a no-op while the window is already following the store.
            model.keepUp()
            // Restarted rather than left running, so coming back is itself a
            // tick and the next one is counted from now. It reads the page back
            // whatever the publishers say, which is what repairs a window that
            // was away while a background pass rewrote the store under it.
            model.startTheClock(.foreground)
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
    /// Where a route goes : an article is presented, everything else is pushed.
    ///
    /// **One rule, in one place.** An article is a place the reader can be, so
    /// it stays a route ; it is simply not a place on a stack. Reading is one
    /// thing at a time and over everything, and a section's stack is where the
    /// reader was before they opened it and where they will be when they put it
    /// down. Every closure that hands a route out goes through here, so no
    /// screen has to know which of the two its rows do.
    private func opening(_ path: Binding<[Route]>) -> (Route) -> Void {
        { route in
            if case .article(let id) = route {
                reading = Reading(id: id)
            } else {
                path.wrappedValue.append(route)
            }
        }
    }

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
                    reading = Reading(id: $0)
                },
                from: id
            )

        // Never reached : `opening(_:)` presents an article rather than
        // putting it on a stack, so nothing appends this one. It stays a route
        // because it is a place the reader can be, and the switch has to say
        // so somewhere.
        case .article:
            EmptyView()

        case .view(let kind):
            ArticleFeedScreen(model: model, kind: kind, zoom: zoom) { reading = Reading(id: $0) }

        case .collection(let kind):
            CollectionScreen(model: model, kind: kind, zoom: zoom) { reading = Reading(id: $0) }

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
