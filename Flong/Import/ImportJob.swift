//
//  ImportJob.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// How much of each source's history to bring.
///
/// **A bound rather than everything, by default.** A FreshRSS instance that has
/// been collecting for five years holds more than the whole budget of section 21
/// allows this store, and an import that quietly pulled all of it would spend a
/// morning on the network to arrive at a device that then purges it. The reader
/// chooses, in articles per source, because that is the unit the API pages in
/// and the only one that bounds the work predictably : a month of a daily paper
/// and a month of a weekly are not the same amount of anything.
nonisolated enum ImportDepth: Int, Hashable, Sendable, CaseIterable, Identifiable {
    case hundred = 100
    case fiveHundred = 500
    case everything = 0

    var id: Int { rawValue }

    /// How many articles to stop at, or `nil` for the whole stream.
    var limit: Int? { self == .everything ? nil : rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .hundred: "The last 100 of each"
        case .fiveHundred: "The last 500 of each"
        case .everything: "Everything"
        }
    }
}

/// An import of a remote account, as it stands.
///
/// **It is written down because it is long.** An account of sixty feeds and
/// twenty thousand articles is minutes of network, and a phone locked in the
/// middle of it is the ordinary case rather than the exception. The row survives
/// the launch, the reader is offered the rest of it when they come back, and
/// nothing already brought in is fetched twice.
///
/// One at a time : starting an import replaces whatever was here. Two accounts
/// being imported at once is not a thing anybody asked for, and the second one
/// can be started when the first is over.
///
/// The API password is not in this row and never will be. It lives in the
/// keychain under this job's identifier, exactly as a feed's credential lives
/// there under the feed's, and it is deleted the moment the import ends.
nonisolated struct ImportJob: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "import_job"

    enum CodingKeys: String, CodingKey {
        case id
        case endpoint
        case username
        case startedAt = "started_at"
        case depth
        case wantsFavourites = "wants_favourites"
        case tookSubscriptions = "took_subscriptions"
        case favouritesContinuation = "favourites_continuation"
        case tookFavourites = "took_favourites"
        case added
        case merged
        case articles
        case favourites
        case favouritesElsewhere = "favourites_elsewhere"
    }

    var id: UUID
    /// Where the API is, already resolved.
    var endpoint: URL
    var username: String
    var startedAt: Date

    /// How many articles per source, or nought for the whole stream.
    var depth: Int
    var wantsFavourites: Bool

    /// Whether the subscriptions have been written, which is the first pass and
    /// the one everything else hangs off.
    var tookSubscriptions: Bool
    /// Where the walk through the starred stream got to.
    var favouritesContinuation: String?
    var tookFavourites: Bool

    /// What has been done so far, so a report survives the interruption too.
    var added: Int
    var merged: Int
    var articles: Int
    var favourites: Int
    /// Favourites of sources this device does not follow, which have nowhere to
    /// go : see ``ServiceImport``.
    var favouritesElsewhere: Int

    init(
        id: UUID = .v7(),
        endpoint: URL,
        username: String,
        startedAt: Date = Date(),
        depth: ImportDepth = .fiveHundred,
        wantsFavourites: Bool = true,
        tookSubscriptions: Bool = false,
        favouritesContinuation: String? = nil,
        tookFavourites: Bool = false,
        added: Int = 0,
        merged: Int = 0,
        articles: Int = 0,
        favourites: Int = 0,
        favouritesElsewhere: Int = 0
    ) {
        self.id = id
        self.endpoint = endpoint
        self.username = username
        self.startedAt = startedAt
        self.depth = depth.rawValue
        self.wantsFavourites = wantsFavourites
        self.tookSubscriptions = tookSubscriptions
        self.favouritesContinuation = favouritesContinuation
        self.tookFavourites = tookFavourites
        self.added = added
        self.merged = merged
        self.articles = articles
        self.favourites = favourites
        self.favouritesElsewhere = favouritesElsewhere
    }

    var account: ServiceAccount { ServiceAccount(endpoint: endpoint, username: username) }
    var wantedDepth: ImportDepth { ImportDepth(rawValue: depth) ?? .everything }
}

/// One source of the account, as the reader decided about it.
///
/// Every subscription the service listed is written down, ticked or not : the
/// row is what the picker was showing, and an import resumed a day later shows
/// the same list rather than asking the service again and finding it changed.
nonisolated struct ImportSource: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "import_source"

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case streamID = "stream_id"
        case address
        case title
        case siteAddress = "site_address"
        case iconAddress = "icon_address"
        case isChosen = "is_chosen"
        case wantsArticles = "wants_articles"
        case continuation
        case fetched
        case isDone = "is_done"
    }

    var jobID: UUID
    /// `feed/<numeric id>`, which is what the stream is read under.
    var streamID: String
    /// The feed document, as the service spelled it.
    var address: String
    var title: String
    var siteAddress: String?
    var iconAddress: String?

    /// Whether the reader ticked it.
    var isChosen: Bool
    /// Whether its history is wanted, which is the tick and the switch together.
    var wantsArticles: Bool

    /// Where the walk through its stream got to, and `nil` at the start.
    var continuation: String?
    var fetched: Int
    var isDone: Bool

    var id: String { streamID }

    init(
        jobID: UUID,
        streamID: String,
        address: String,
        title: String = "",
        siteAddress: String? = nil,
        iconAddress: String? = nil,
        isChosen: Bool = true,
        wantsArticles: Bool = false,
        continuation: String? = nil,
        fetched: Int = 0,
        isDone: Bool = false
    ) {
        self.jobID = jobID
        self.streamID = streamID
        self.address = address
        self.title = title
        self.siteAddress = siteAddress
        self.iconAddress = iconAddress
        self.isChosen = isChosen
        self.wantsArticles = wantsArticles
        self.continuation = continuation
        self.fetched = fetched
        self.isDone = isDone
    }
}

nonisolated extension ImportSource {
    enum Columns {
        static let jobID = Column(CodingKeys.jobID)
        static let isChosen = Column(CodingKeys.isChosen)
        static let wantsArticles = Column(CodingKeys.wantsArticles)
        static let isDone = Column(CodingKeys.isDone)
    }
}

/// Where an import that is not finished is kept.
nonisolated struct ImportJobStore: Sendable {
    private let database: AppDatabase

    init(_ database: AppDatabase) {
        self.database = database
    }

    /// The import waiting to be finished, where there is one.
    func job() async throws -> ImportJob? {
        try await database.writer.read { db in try ImportJob.fetchOne(db) }
    }

    /// Every source of it, in the order the picker showed them.
    func sources(of job: UUID) async throws -> [ImportSource] {
        try await database.writer.read { db in
            try ImportSource
                .filter(ImportSource.Columns.jobID == job)
                .order(Column(ImportSource.CodingKeys.title))
                .fetchAll(db)
        }
    }

    /// The sources still to be walked through, which is what a resumption asks.
    func outstanding(of job: UUID) async throws -> [ImportSource] {
        try await database.writer.read { db in
            try ImportSource
                .filter(ImportSource.Columns.jobID == job)
                .filter(ImportSource.Columns.wantsArticles == true && ImportSource.Columns.isDone == false)
                .order(Column(ImportSource.CodingKeys.title))
                .fetchAll(db)
        }
    }

    /// Starts one, replacing whatever was there.
    ///
    /// One transaction, so an import never exists without the list of what it is
    /// importing.
    func start(_ job: ImportJob, sources: [ImportSource]) async throws {
        try await database.writer.write { db in
            try ImportJob.deleteAll(db)
            try job.insert(db)
            for source in sources { try source.insert(db) }
        }
    }

    func save(_ job: ImportJob) async throws {
        try await database.writer.write { db in try job.update(db) }
    }

    func save(_ source: ImportSource) async throws {
        try await database.writer.write { db in try source.update(db) }
    }

    /// Takes the import away, finished or abandoned.
    ///
    /// The sources go with it, through the foreign key. What does not go with it
    /// is anything it brought in : the subscriptions and the articles are the
    /// reader's now and have nothing further to do with the account they came
    /// from.
    func finish() async throws {
        try await database.writer.write { db in _ = try ImportJob.deleteAll(db) }
    }
}
