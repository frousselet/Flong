//
//  RootView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers

/// The window content.
///
/// Everything hangs off the store, so a window without one has nothing to show
/// and says so rather than pretending to be empty.
struct RootView: View {
    let database: AppDatabase?

    var body: some View {
        if let database {
            ReadingView(database: database)
        } else {
            ContentUnavailableView {
                Label("Storage unavailable", systemImage: "externaldrive.trianglebadge.exclamationmark")
            } description: {
                Text("Flong could not open its database.")
            }
        }
    }
}

/// The three levels of section 16 : sidebar, list, article.
///
/// One `NavigationSplitView` serves the three platforms. It collapses to a stack
/// on iPhone by itself, which is what keeps the three columns of iPad and Mac
/// from becoming a second interface to maintain.
struct ReadingView: View {
    @State private var model: AppModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isAddingFeed = false
    @State private var isChoosingFile = false
    @Environment(\.scenePhase) private var scenePhase

    init(database: AppDatabase) {
        _model = State(initialValue: AppModel(database: database))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model, isAddingFeed: $isAddingFeed, isChoosingFile: $isChoosingFile)
        } content: {
            ArticleListView(model: model)
        } detail: {
            ArticleReaderView(model: model)
        }
        .task {
            await model.load()
            await model.synchronizeSpotlight()
            await model.refreshDue()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            // A kept article opened from the system search opens here.
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            Task { await model.open(spotlightIdentifier: identifier) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground is the main refresh, the background
            // one being opportunistic by nature.
            guard phase == .active else { return }
            Task { await model.refreshDue() }
        }
        .sheet(isPresented: $isAddingFeed) {
            AddFeedView { address in await model.addFeed(at: address) }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.opmlTypes) { result in
            guard case .success(let url) = result else { return }
            Task { await model.importOPML(from: url) }
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

    /// What the file chooser offers. An exported file is as often typed as plain
    /// XML as it is as OPML.
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

#Preview {
    RootView(database: try? AppDatabase.inMemory())
}
