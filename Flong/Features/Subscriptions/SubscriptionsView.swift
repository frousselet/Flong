//
//  SubscriptionsView.swift
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

/// The feeds Flong follows, and the way in for an OPML file.
///
/// It stands in for the sidebar of section 16 of the specification, which
/// arrives with the reading interface. What it shows is already the truth of the
/// store : the folder tree, the titles and the addresses.
struct SubscriptionsView: View {
    @State private var model: SubscriptionsModel
    @State private var isChoosingFile = false

    init(database: AppDatabase) {
        _model = State(initialValue: SubscriptionsModel(database: database))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Subscriptions"))
                .toolbar {
                    ToolbarItem {
                        Button {
                            isChoosingFile = true
                        } label: {
                            Label("Import an OPML file", systemImage: "square.and.arrow.down")
                        }
                        .disabled(model.isImporting)
                    }
                }
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
            Text("Import failed"),
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
            presenting: model.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.sections.isEmpty {
            ContentUnavailableView {
                Label("No feed yet", systemImage: "dot.radiowaves.up.forward")
            } description: {
                Text("Import an OPML file to bring your subscriptions over.")
            } actions: {
                Button("Import an OPML file") { isChoosingFile = true }
                    .disabled(model.isImporting)
            }
        } else {
            List {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.feeds) { feed in
                            row(for: feed)
                        }
                    } header: {
                        if let folder = section.folder {
                            Text(verbatim: folder)
                        } else {
                            Text("No folder")
                        }
                    }
                }
            }
        }
    }

    private func row(for feed: Feed) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: feed.title)
            Text(verbatim: feed.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
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
    SubscriptionsView(database: try! AppDatabase.inMemory())
}
