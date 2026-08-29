//
//  SubscriptionsModel.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// The feeds of one folder, as a list shows them.
struct SubscriptionSection: Identifiable, Hashable {
    /// The folder path, `nil` for the feeds outside every folder.
    let folder: String?
    let feeds: [Feed]

    var id: String { folder ?? "" }
}

/// Why an import stopped.
enum ImportFailure: Hashable, Identifiable {
    case unreadableFile
    case notOPML
    case notSaved

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .unreadableFile: "This file could not be opened."
        case .notOPML: "This file could not be read as OPML."
        case .notSaved: "The subscriptions could not be saved."
        }
    }
}

/// What the subscriptions screen shows and does.
@Observable
final class SubscriptionsModel {
    private let store: SubscriptionStore
    private let opml: OPMLImport

    private(set) var sections: [SubscriptionSection] = []
    private(set) var isImporting = false

    /// The summary of the last import, until the reader dismisses it.
    var report: OPMLImportReport?
    var failure: ImportFailure?

    init(database: AppDatabase) {
        let store = SubscriptionStore(database)
        self.store = store
        self.opml = OPMLImport(store)
    }

    func load() async {
        do {
            sections = Self.sections(of: try await store.feeds())
        } catch {
            Log.store.error("The subscriptions could not be read : \(error, privacy: .public)")
        }
    }

    func importOPML(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            report = try await opml(contentsOf: url)
            await load()
        } catch let error as OPMLError {
            // Unreadable bytes and well formed XML that is not OPML come to the
            // same thing for the reader : this file is not a subscription list.
            failure = .notOPML
            Log.store.error("The file is not an OPML document : \(String(describing: error), privacy: .public)")
        } catch let error as CocoaError {
            failure = .unreadableFile
            Log.store.error("The file could not be read : \(error, privacy: .public)")
        } catch {
            failure = .notSaved
            Log.store.error("The import could not be saved : \(error, privacy: .public)")
        }
    }

    /// Folders first, in the reader's collation, and the unfiled feeds last.
    private static func sections(of feeds: [Feed]) -> [SubscriptionSection] {
        let grouped = Dictionary(grouping: feeds, by: \.folder)

        let folders =
            grouped.keys
            .compactMap { $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var sections = folders.map { SubscriptionSection(folder: $0, feeds: grouped[$0] ?? []) }
        if let unfiled = grouped[nil], !unfiled.isEmpty {
            sections.append(SubscriptionSection(folder: nil, feeds: unfiled))
        }
        return sections
    }
}
