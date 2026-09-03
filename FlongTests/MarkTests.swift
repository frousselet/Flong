//
//  MarkTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB
import Testing

@testable import Flong

/// What the reader says about an article, and what it costs them to say it.
///
/// There is one article and no copy of it : starring, writing on and filing all
/// happen on the row itself. These check the three things that used to be a
/// second table's job and are now the row's own, and the one thing that has to
/// hold for the whole design to be safe : a purge never takes a marked article.
@Suite("What the reader says about an article")
struct MarkTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let collections: CollectionStore
    private let feed: Feed
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() async throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        collections = CollectionStore(database)
        feed = try await subscriptions.subscribe(
            to: Subscription(address: "https://quotidien.example.com/f.xml", title: "Le Quotidien")
        ).feed
    }

    @discardableResult
    private func add(_ title: String, body: String = "Le corps de l'article.", age: TimeInterval = 3600) async throws
        -> Entry
    {
        var entry = Entry(
            feedID: feed.id,
            guid: "urn:example:\(title)",
            url: URL(string: "https://example.com/\(abs(title.hashValue))"),
            title: title,
            excerpt: String(body.prefix(40)),
            author: "Camille Dupuis",
            language: "fr",
            publishedAt: now.addingTimeInterval(-age),
            receivedAt: now.addingTimeInterval(-age)
        )
        entry.imageURL = URL(string: "https://example.com/covers/\(abs(title.hashValue)).jpg")

        try await database.writer.write { db in
            try entry.insert(db)
            try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(body)</p>", plainText: body).insert(db)
        }
        return entry
    }

    // MARK: - The three ways of saying something

    @Test("Starring an article puts it in the favourites and nowhere else")
    func starring() async throws {
        let starred = try await add("Étoilé")
        try await add("Ignoré")

        try await articles.setStarred([starred.id], to: true)

        let favourites = try await articles.summaries(in: .builtIn(.starred))
        #expect(favourites.map(\.title) == ["Étoilé"])
        #expect(try await articles.summaries(in: .builtIn(.annotated)).isEmpty)
    }

    @Test("Writing on an article puts it in the notes, starred or not")
    func annotating() async throws {
        let noted = try await add("Annoté")

        try await articles.annotate(noted.id, with: "À relire")

        #expect(try await articles.annotation(of: noted.id) == "À relire")
        #expect(try await articles.summaries(in: .builtIn(.annotated)).map(\.title) == ["Annoté"])
        // A note is not a star : the two are different sentences and neither
        // implies the other.
        #expect(try await articles.summaries(in: .builtIn(.starred)).isEmpty)
    }

    @Test("An emptied note is no note")
    func erasingANote() async throws {
        let noted = try await add("Annoté")

        try await articles.annotate(noted.id, with: "À relire")
        try await articles.annotate(noted.id, with: "   ")

        #expect(try await articles.annotation(of: noted.id) == nil)
        #expect(try await articles.summaries(in: .builtIn(.annotated)).isEmpty)
    }

    @Test("Unstarring a filed article leaves the filing alone")
    func unstarringKeepsTheFiling() async throws {
        let both = try await add("Les deux")
        _ = try await collections.create("Typographie")
        try await collections.add([both.id], to: "Typographie")
        try await articles.setStarred([both.id], to: true)

        try await articles.setStarred([both.id], to: false)

        // The bug this stands against : unstarring used to let go of the whole
        // copy, and every collection it was in emptied with it.
        #expect(try await collections.collections(of: both.id) == ["Typographie"])
        #expect(try await articles.summaries(in: .made("Typographie")).map(\.title) == ["Les deux"])
        #expect(try await articles.summaries(in: .builtIn(.starred)).isEmpty)
    }

    @Test("A square is counted for each way of marking, and neither counts the other")
    func builtInCollections() async throws {
        let starred = try await add("Étoilé")
        let noted = try await add("Annoté")
        try await add("Ni l'un ni l'autre")

        try await articles.setStarred([starred.id], to: true)
        try await articles.annotate(noted.id, with: "À relire")

        let built = try await articles.builtInCollections()
        let favourites = try #require(built.first { $0.kind == ArticleCollection.Kind.builtIn(.starred) })
        let notes = try #require(built.first { $0.kind == ArticleCollection.Kind.builtIn(.annotated) })

        #expect(favourites.count == 1)
        #expect(favourites.covers.count == 1)
        #expect(notes.count == 1)
    }

    @Test("A reader who has marked nothing sees no squares at all")
    func nothingMarked() async throws {
        try await add("Ignoré")
        #expect(try await articles.builtInCollections().isEmpty)
    }

    // MARK: - What the indexer is given

    @Test("Spotlight is offered what the reader chose article by article")
    func chosenOneAtATime() async throws {
        let starred = try await add("Étoilé")
        let noted = try await add("Annoté")
        let filed = try await add("Classé")
        try await add("Ignoré")

        try await articles.setStarred([starred.id], to: true)
        try await articles.annotate(noted.id, with: "À relire")
        _ = try await collections.create("Typographie")
        try await collections.add([filed.id], to: "Typographie")

        let chosen = try await articles.chosen()
        #expect(Set(chosen.map(\.title)) == ["Étoilé", "Annoté", "Classé"])
        // The body comes along, since it is what a system-wide search matches.
        #expect(chosen.allSatisfy { $0.plainText?.isEmpty == false })

        // And narrowed, for the one article a star just changed.
        #expect(try await articles.chosen([starred.id, noted.id]).count == 2)
        #expect(try await articles.chosen([starred.id]).map(\.title) == ["Étoilé"])
    }

    @Test("Singling out a publisher chooses everything it has served")
    func chosenBySource() async throws {
        try await add("Premier")
        try await add("Second")
        #expect(try await articles.chosen().isEmpty)

        try await subscriptions.setFavourite(feed.id, true)
        #expect(Set(try await articles.chosen().map(\.title)) == ["Premier", "Second"])

        // And the decision is undone as plainly as it was made : nothing was
        // starred, so nothing stays behind.
        try await subscriptions.setFavourite(feed.id, false)
        #expect(try await articles.chosen().isEmpty)
    }

    @Test("Singling out a writer chooses everything they signed")
    func chosenByAuthor() async throws {
        let signed = try await add("Signé")
        let other = try await add("Anonyme")
        try await database.writer.write { db in
            try AuthorStore.index(signed.id, byline: "Claire Ancelin", in: db)
            try AuthorStore.index(other.id, byline: nil, in: db)
        }

        let authors = AuthorStore(database)
        try await authors.setFavourite("Claire Ancelin", true)
        #expect(try await articles.chosen().map(\.title) == ["Signé"])

        try await authors.setFavourite("Claire Ancelin", false)
        #expect(try await articles.chosen().isEmpty)
    }

    @Test("A favourite is worth its most recent articles and no more")
    func favouritesAreCapped() async throws {
        // Oldest first, so the two newest are the last two added.
        let ordered = try await [
            add("Le plus ancien", age: 4 * 3600),
            add("Avant-dernier", age: 3 * 3600),
            add("Avant-veille", age: 2 * 3600),
            add("Le plus récent", age: 3600),
        ]
        try await database.writer.write { db in
            for entry in ordered { try AuthorStore.index(entry.id, byline: "Claire Ancelin", in: db) }
        }

        try await subscriptions.setFavourite(feed.id, true)
        try await AuthorStore(database).setFavourite("Claire Ancelin", true)

        // The cap is per source and per writer, and these four are one of each,
        // so both ways of choosing are cut at the same two articles.
        let chosen = try await articles.chosen(perFavourite: 2)
        #expect(Set(chosen.map(\.title)) == ["Le plus récent", "Avant-veille"])
        #expect(try await articles.choices(perFavourite: 2).count == 2)

        // **A star is not capped.** The oldest article of a prolific source is
        // out of the index until the reader says otherwise, and saying so is
        // what puts it back.
        try await articles.setStarred([ordered[0].id], to: true)
        let starred = try await articles.chosen(perFavourite: 2)
        #expect(Set(starred.map(\.title)) == ["Le plus récent", "Avant-veille", "Le plus ancien"])
    }

    @Test("The cap is the system index's and never the collection's")
    func theCollectionsAreNotCapped() async throws {
        try await add("Premier", age: 2 * 3600)
        try await add("Second", age: 3600)
        try await subscriptions.setFavourite(feed.id, true)

        // What the square opens on is everything the publisher served. Spotlight
        // is the one place a favourite is rationed, because it is the one place
        // with a budget that is not Flong's own.
        #expect(try await articles.summaries(in: .builtIn(.favouriteSources)).count == 2)
    }

    @Test("What the index should hold is answered without reading a single body")
    func choices() async throws {
        let starred = try await add("Étoilé")
        try await add("Ignoré")
        try await articles.setStarred([starred.id], to: true)

        let choices = try await articles.choices()
        #expect(choices.map(\.id) == [starred.id])
        // The same store answered twice is the same answer, which is the whole
        // point : it is compared with what Spotlight was last told.
        #expect(try await articles.choices() == choices)
    }

    // MARK: - What a purge may not take

    @Test("A purge by age spares every marked article, however it was marked")
    func purgingSparesTheMarked() async throws {
        let starred = try await add("Étoilé", age: 400 * 86400)
        let noted = try await add("Annoté", age: 400 * 86400)
        let filed = try await add("Classé", age: 400 * 86400)
        try await add("Oublié", age: 400 * 86400)

        try await articles.setStarred([starred.id], to: true)
        try await articles.annotate(noted.id, with: "À relire")
        _ = try await collections.create("Typographie")
        try await collections.add([filed.id], to: "Typographie")

        let summary = try await Retention(database).purge(.bounded, now: now)

        // Only the one nobody said anything about.
        #expect(summary.byAge == 1)
        #expect(try await articles.count(.all, now: now) == 3)
        #expect(try await collections.collections(of: filed.id) == ["Typographie"])
    }

    @Test("A purge by volume spares them too")
    func purgingByVolumeSparesTheMarked() async throws {
        var starred: [UUID] = []
        var filed: [UUID] = []
        for index in 0..<200 {
            let entry = try await add("Article \(index)", body: String(repeating: "x", count: 2048))
            if index < 5 { starred.append(entry.id) }
            if index >= 5 && index < 10 { filed.append(entry.id) }
        }
        try await articles.setStarred(starred, to: true)
        _ = try await collections.create("Typographie")
        try await collections.add(filed, to: "Typographie")

        let retention = Retention(database)
        var policy = RetentionPolicy.bounded
        policy.maximumAge = nil
        policy.maximumBytes = try await retention.size() / 2
        _ = try await retention.purge(policy, now: now)

        #expect(try await articles.summaries(in: .builtIn(.starred)).count == 5)
        #expect(try await articles.summaries(in: .made("Typographie")).count == 5)
    }
}
