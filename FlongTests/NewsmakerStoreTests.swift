//
//  NewsmakerStoreTests.swift
//  FlongTests
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import GRDB
import Testing

@testable import Flong

@Suite("The people the articles are about")
struct NewsmakerStoreTests {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let collections: CollectionStore
    private let newsmakers: NewsmakerStore
    private let now = Date(timeIntervalSince1970: 1_787_646_600)

    init() throws {
        database = try AppDatabase.inMemory()
        subscriptions = SubscriptionStore(database)
        articles = ArticleStore(database)
        collections = CollectionStore(database)
        newsmakers = NewsmakerStore(database)
    }

    /// One article, stored the way ingestion stores it : nobody is read out of
    /// it here, since reading is the job's work and not the write's.
    @discardableResult
    private func article(
        _ title: String,
        saying text: String? = nil,
        signedBy author: String? = nil,
        image: URL? = nil,
        at received: Date? = nil,
        from source: String = "https://feeds.papier.example.com/une.xml"
    ) async throws -> Entry {
        let feed = try await subscriptions.subscribe(
            to: Subscription(address: source, title: "Le Papier")
        ).feed

        var entry = Entry(
            feedID: feed.id,
            guid: "urn:\(title)",
            title: title,
            author: author,
            language: "fr",
            receivedAt: received ?? now,
            imageURL: image
        )
        entry.hasMedia = false
        try await database.writer.write { db in
            try entry.insert(db)
            if let text {
                try EntryBody(entryID: entry.id, sanitizedHTML: "<p>\(text)</p>", plainText: text).insert(db)
            }
        }
        return entry
    }

    /// One person, in as many articles as the directory asks for.
    ///
    /// The tests go through the threshold rather than round it : what the
    /// directory shows is what five articles said, not what one did.
    private func articles(
        _ count: Int,
        saying text: String,
        from source: String = "https://feeds.papier.example.com/une.xml"
    ) async throws {
        for number in 0..<count {
            try await article("Article \(number) de \(source)", saying: text, from: source)
        }
    }

    /// Runs the job to its end, which is what a pass does.
    private func readEverything() async throws {
        while true {
            let batch = try await newsmakers.unread()
            guard !batch.isEmpty else { break }
            try await newsmakers.read(batch)
        }
    }

    // MARK: - Reading a person out of an article

    @Test("A headline names the people it is about, in the order it names them")
    func headline() {
        let found = Newsmaker.people(inTitle: "Emmanuel Macron reçoit Donald Trump à Paris", language: "fr")

        #expect(found.map(\.name) == ["Emmanuel Macron", "Donald Trump"])
        // Paris is a place and Flong is a directory of people, so it is not
        // here : a country in a list of names is a row nobody can follow.
        #expect(!found.contains { $0.name == "Paris" })
    }

    @Test("A paper names somebody in full once and by their surname after, and that is one person")
    func surnames() {
        let found = Newsmaker.people(
            inTitle: "Trump donne dix jours à l'Iran",
            text: """
                Donald Trump a donné dix jours à l'Iran pour revenir à la table des négociations. \
                Le président américain s'est entretenu avec Emmanuel Macron mardi soir. \
                Trump a répété que toutes les options restaient sur la table. \
                Macron a appelé à la retenue.
                """,
            language: "fr"
        )

        // Two people and not four : `Trump` and `Macron` are the same two
        // written short, and their mentions are theirs.
        #expect(found.map(\.name) == ["Donald Trump", "Emmanuel Macron"])
        #expect(!found.contains { $0.name == "Trump" || $0.name == "Macron" })
        // The full name is written once here and the short one twice, so a
        // count above one is the fold having happened. How many exactly is the
        // tagger's answer rather than this rule's, and pinning that here would
        // be a test that fails on an operating system update.
        #expect(found.first { $0.name == "Donald Trump" }.map { $0.times > 1 } == true)
    }

    @Test("A surname two people in one article share folds into neither of them")
    func ambiguity() {
        let found = Newsmaker.people(
            inTitle: "Le procès",
            text: """
                Donald Trump a parlé mardi. Melania Trump était présente. \
                Trump a répété que rien ne changerait. Trump est attendu jeudi.
                """,
            language: "fr"
        )

        // There is no telling which of the two the short name meant, so nothing
        // is guessed and it keeps a row of its own.
        #expect(Set(found.map(\.name)) == ["Donald Trump", "Melania Trump", "Trump"])
        #expect(found.first?.name == "Trump")
        #expect(found.first?.times == 2)
    }

    @Test("Whoever signed the piece is not somebody it is about")
    func bylines() {
        let found = Newsmaker.people(
            inTitle: "Un entretien",
            text: """
                Claire Ancelin a rencontré Emmanuel Macron mardi. Macron a refusé de commenter. \
                Claire Ancelin est journaliste au Monde.
                """,
            language: "fr",
            signedBy: "Claire Ancelin"
        )

        // Plenty of publishers print the byline again at the foot of the prose.
        // Left in, the writer would be in both directories at once.
        #expect(found.map(\.name) == ["Emmanuel Macron"])
    }

    @Test("A span the tagger joined across a verb is the people it joined, and not a third one")
    func overJoined() {
        // `joinNames` hands back a whole clause when a sentence puts two names
        // either side of a verb. Kept whole it is somebody who exists nowhere,
        // and neither of the two real people is ever findable.
        #expect(Newsmaker.names(inSpan: "Eric Zemmour déborde Sarah Knafo") == ["Eric Zemmour", "Sarah Knafo"])
        #expect(Newsmaker.names(inSpan: "Céline Dion chante") == ["Céline Dion"])
        #expect(Newsmaker.names(inSpan: "Jean-Luc Mélenchon a-t") == ["Jean-Luc Mélenchon"])
    }

    @Test("A particle is lower case and is part of the name all the same")
    func particles() {
        #expect(Newsmaker.names(inSpan: "Dominique de Villepin") == ["Dominique de Villepin"])
        #expect(Newsmaker.names(inSpan: "Mathieu van der Poel") == ["Mathieu van der Poel"])
        #expect(Newsmaker.names(inSpan: "Steven le Hyaric") == ["Steven le Hyaric"])
        // A particle left hanging is the start of a name the cut took away.
        #expect(Newsmaker.names(inSpan: "Emmanuel Macron de") == ["Emmanuel Macron"])
    }

    @Test("The acronym a newsroom staples in front of a name is not part of the name")
    func acronyms() {
        #expect(Newsmaker.names(inSpan: "PDG Patrick Pouyanné") == ["Patrick Pouyanné"])
        #expect(Newsmaker.names(inSpan: "LFI Sébastien Delogu") == ["Sébastien Delogu"])
        // Two words have to be left after it, which is what keeps a real name
        // in capitals out of the rule.
        #expect(Newsmaker.names(inSpan: "JR Smith") == ["JR Smith"])
    }

    @Test("A word set entirely in capitals is an acronym and not a person")
    func capitals() {
        // A technology, a job and a French statute, every one of them handed
        // over by the tagger as somebody's name.
        #expect(Newsmaker.names(inSpan: "AI").isEmpty)
        #expect(Newsmaker.names(inSpan: "CEO").isEmpty)
        #expect(Newsmaker.names(inSpan: "SREN").isEmpty)
        #expect(Newsmaker.names(inSpan: "Emmanuel Macron") == ["Emmanuel Macron"])
    }

    @Test("An article about nobody is about nobody")
    func nobody() {
        #expect(Newsmaker.people(inTitle: "Le budget 2027 en cinq graphiques", language: "fr").isEmpty)
        #expect(Newsmaker.people(inTitle: "", language: "fr").isEmpty)
    }

    @Test("The language is believed where the feed stated one, and guessed where it did not")
    func languages() {
        let stated = Newsmaker.people(
            inTitle: "Une rencontre",
            text: "Donald Trump a parlé mardi soir. Emmanuel Macron lui a répondu mercredi matin.",
            language: "fr"
        )
        let guessed = Newsmaker.people(
            inTitle: "Une rencontre",
            text: "Donald Trump a parlé mardi soir. Emmanuel Macron lui a répondu mercredi matin."
        )

        #expect(Set(stated.map(\.name)) == ["Donald Trump", "Emmanuel Macron"])
        #expect(Set(guessed.map(\.name)) == Set(stated.map(\.name)))
    }

    @Test("Only as much of an article is read as the bound allows")
    func length() {
        let filler = String(repeating: "Il a plu toute la semaine sur la ville. ", count: 1_200)
        #expect(filler.count > Newsmaker.lengthRead)

        let found = Newsmaker.people(
            inTitle: "La pluie",
            text: filler + " Donald Trump a parlé mardi soir.",
            language: "fr"
        )
        // Past the bound a piece has said who it is about many times over, and
        // the tagger costs time per character over the whole corpus.
        #expect(found.isEmpty)
    }

    // MARK: - What the job leaves behind

    @Test("An article is read once, and one that named nobody is never asked about again")
    func queue() async throws {
        try await articles(Newsmaker.leastArticles, saying: "Donald Trump a parlé mardi soir.")
        try await article("Le budget en cinq graphiques", saying: "Les recettes reculent de trois points.")

        #expect(try await newsmakers.outstandingCount() == Newsmaker.leastArticles + 1)
        try await readEverything()
        #expect(try await newsmakers.outstandingCount() == 0)

        // The last named nobody, which is a real answer : it has no rows and
        // it is out of the queue all the same.
        #expect(try await newsmakers.all().map(\.name) == ["Donald Trump"])
    }

    @Test("The queue hands over what arrived last first, which is what a pass has to read before it speaks")
    func newestFirst() async throws {
        try await article("Vieux", saying: "Donald Trump a parlé mardi soir.", at: now.addingTimeInterval(-3600))
        try await article("Neuf", saying: "Emmanuel Macron a parlé mercredi matin.", at: now)

        // A refresh announces what it brought, and the watermark moves whether
        // it said anything or not : a pass that read the backlog first would
        // let the new arrivals past unread, and a notice about somebody named
        // in one of them would never be posted at all.
        #expect(try await newsmakers.unread(limit: 1).map(\.title) == ["Neuf"])
    }

    @Test("Reading an article twice says it once")
    func idempotent() async throws {
        let entry = try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()

        try await database.writer.write { db in try NewsmakerStore.reread(entry.id, in: db) }
        try await readEverything()

        // Asked of the person rather than of the directory : one article is
        // below the threshold, and what is being tested here is the rows.
        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.count == 1)
    }

    @Test("An article a publisher rewrote keeps nobody it no longer names")
    func rewritten() async throws {
        let entry = try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()
        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.count == 1)

        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE entry_body SET plain_text = ? WHERE entry_id = ?",
                arguments: ["Emmanuel Macron a parlé mercredi matin.", entry.id]
            )
            try NewsmakerStore.reread(entry.id, in: db)
        }
        try await readEverything()

        #expect(try await newsmakers.newsmaker(named: "Donald Trump") == nil)
        #expect(try await newsmakers.newsmaker(named: "Emmanuel Macron")?.count == 1)
    }

    @Test("A duplicate and a hidden article are not read : neither is shown anywhere")
    func unshown() async throws {
        let first = try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        let second = try await article("La même", saying: "Emmanuel Macron a parlé mercredi.")

        try await database.writer.write { db in
            try db.execute(sql: "UPDATE entry SET duplicate_of = ? WHERE id = ?", arguments: [first.id, second.id])
        }

        #expect(try await newsmakers.outstandingCount() == 1)
        try await readEverything()
        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.count == 1)
        #expect(try await newsmakers.newsmaker(named: "Emmanuel Macron") == nil)
    }

    // MARK: - Who there is

    @Test("Two articles about one person are one row and a count of two")
    func counting() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await article("Une autre", saying: "Donald Trump est attendu jeudi.")
        try await readEverything()

        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.count == 2)
    }

    @Test("A row names the publishers writing about them, the ones writing most first")
    func publishers() async throws {
        try await article(
            "Une rencontre", saying: "Donald Trump a parlé mardi soir.",
            from: "https://feeds.papier.example.com/une.xml"
        )
        try await article(
            "Une autre", saying: "Donald Trump est attendu jeudi.",
            from: "https://feeds.papier.example.com/monde.xml"
        )
        try await article(
            "Une troisième", saying: "Donald Trump a répondu vendredi.",
            from: "https://feeds.gazette.example.com/une.xml"
        )
        try await readEverything()

        // Two of the three feeds belong to one publisher, which is why it leads.
        // The publisher and never the desk : two feeds served from one address
        // are one mark. The host is taken as it stands, `feeds.` included, for
        // the reason the sources list takes it that way.
        let trump = try #require(try await newsmakers.newsmaker(named: "Donald Trump"))
        #expect(trump.publishers == ["feeds.papier.example.com", "feeds.gazette.example.com"])
        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.publishers == trump.publishers)
    }

    @Test("The names come back in the reader's order and not in byte order")
    func ordering() async throws {
        // Through the favourites, so that what is being tested is the sort and
        // not which of two names a model happens to recognize.
        try await newsmakers.setFavourite("Zola", true)
        try await newsmakers.setFavourite("Éluard", true)

        // Byte order would put `Zola` first : a capital E with an acute accent
        // starts with a higher byte than a Z.
        #expect(try await newsmakers.all().map(\.name) == ["Éluard", "Zola"])
    }

    @Test("A name nothing and nobody carries has no page")
    func unknown() async throws {
        #expect(try await newsmakers.newsmaker(named: "Personne") == nil)
    }

    @Test("One person's page holds what is written about them")
    func page() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await article("Sans personne", saying: "Les recettes reculent de trois points.")
        try await readEverything()

        let found = try await articles.summaries(.newsmaker("Donald Trump"))
        #expect(found.map(\.title) == ["Une rencontre"])
    }

    // MARK: - The reader's own

    @Test("Singling somebody out marks them and stars nothing")
    func favourite() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()

        try await newsmakers.setFavourite("Donald Trump", true)

        #expect(try await newsmakers.isFavourite("Donald Trump"))
        #expect(try await newsmakers.favourites() == ["Donald Trump"])
        #expect(try await newsmakers.all().first?.isFavourite == true)
        // Section 13 keeps the star a judgement about the article itself.
        #expect(try await articles.summaries(.starred).isEmpty)
    }

    @Test("A favourite nobody here names is still in the list, with a count of nothing")
    func favouriteWithNothing() async throws {
        try await newsmakers.setFavourite("Emmanuel Macron", true)

        let found = try await newsmakers.all()
        #expect(found.map(\.name) == ["Emmanuel Macron"])
        #expect(found.first?.count == 0)
        // The page about them exists all the same : it is a decision the reader
        // made, and they have to be able to see it and undo it.
        #expect(try await newsmakers.newsmaker(named: "Emmanuel Macron")?.isFavourite == true)
    }

    @Test("Taking the favourite back leaves the person in the list and nothing else behind")
    func unfavourite() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()

        try await newsmakers.setFavourite("Donald Trump", true)
        // A favourite is in the directory whatever their count.
        #expect(try await newsmakers.all().map(\.name) == ["Donald Trump"])

        try await newsmakers.setFavourite("Donald Trump", false)

        #expect(try await newsmakers.favourites().isEmpty)
        // And with the decision taken back, one article is one article : they
        // leave the directory and the rows about them stay where they were.
        #expect(try await newsmakers.all().isEmpty)
        #expect(try await newsmakers.newsmaker(named: "Donald Trump")?.count == 1)
    }

    @Test("Asking to be told about somebody singles nobody out, and the other way round")
    func notifying() async throws {
        try await newsmakers.setNotifies("Emmanuel Macron", true)

        #expect(try await newsmakers.notified() == ["Emmanuel Macron"])
        #expect(try await newsmakers.favourites().isEmpty)
        #expect(try await newsmakers.newsmaker(named: "Emmanuel Macron")?.notifies == true)

        try await newsmakers.setNotifies("Emmanuel Macron", false)
        #expect(try await newsmakers.notified().isEmpty)
    }

    @Test("An article naming somebody the reader asked about is announced under their name")
    func announced() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()
        try await newsmakers.setNotifies("Donald Trump", true)

        let arrived = try await articles.arrived(since: now.addingTimeInterval(-60))
        #expect(arrived.map(\.title) == ["Une rencontre"])
        // The person and not the paper : asking about somebody is the most
        // particular of the requests, so it is what the notice is headed with.
        #expect(arrived.first?.newsmaker == "Donald Trump")
        #expect(arrived.first?.subject == "Donald Trump")
    }

    // MARK: - What the directory leaves out

    @Test("Somebody too few articles name is not in the directory, and their rows are there all the same")
    func threshold() async throws {
        try await articles(Newsmaker.leastArticles - 1, saying: "Emmanuel Macron a parlé mercredi matin.")
        try await readEverything()

        // The long tail is people one piece mentioned once, and a directory
        // nobody can read is a directory nobody opens.
        #expect(try await newsmakers.all().isEmpty)
        // Nothing was thrown away : the threshold is a rule about the question
        // the directory asks, and the next article is what carries them over.
        #expect(try await newsmakers.newsmaker(named: "Emmanuel Macron")?.count == Newsmaker.leastArticles - 1)

        try await article("Une de plus", saying: "Emmanuel Macron a parlé jeudi.")
        try await readEverything()

        #expect(try await newsmakers.all().map(\.name) == ["Emmanuel Macron"])
    }

    @Test("A decision the reader made is never hidden by the threshold")
    func decisionsAreExempt() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await article("Une autre", saying: "Emmanuel Macron a parlé mercredi matin.")
        try await readEverything()
        #expect(try await newsmakers.all().isEmpty)

        // One singled out, one asked about : two different decisions, and both
        // put the person in the directory so the decision can be undone.
        try await newsmakers.setFavourite("Donald Trump", true)
        try await newsmakers.setNotifies("Emmanuel Macron", true)

        #expect(try await newsmakers.all().map(\.name) == ["Donald Trump", "Emmanuel Macron"])
        #expect(try await newsmakers.collections().first?.count == 2)
    }

    // MARK: - The two squares

    @Test("The newsmakers square counts people, and the favourites square counts articles")
    func squares() async throws {
        try await articles(Newsmaker.leastArticles, saying: "Donald Trump a parlé mardi soir.")
        try await article("Une rencontre", saying: "Emmanuel Macron a parlé mercredi matin.")
        try await readEverything()
        try await newsmakers.setFavourite("Donald Trump", true)

        let found = try await newsmakers.collections()
        // **The square counts the rows the list will show.** Trump clears the
        // threshold ; Macron, named once, does not, and the number under a
        // square that opens on a list has to be the length of that list.
        #expect(found.first { $0.kind == .builtIn(.newsmakers) }?.count == 1)
        #expect(try await newsmakers.all().count == 1)
        // The favourites square counts articles rather than people.
        #expect(found.first { $0.kind == .builtIn(.favouriteNewsmakers) }?.count == Newsmaker.leastArticles)
    }

    @Test("Neither square is drawn when there is nothing in it")
    func emptySquares() async throws {
        #expect(try await newsmakers.collections().isEmpty)

        // Named by one article, which is not enough : nothing is drawn at all
        // rather than a square opening on nobody.
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()
        #expect(try await newsmakers.collections().isEmpty)

        try await articles(Newsmaker.leastArticles, saying: "Emmanuel Macron a parlé mercredi matin.")
        try await readEverything()

        // The directory, and no favourites square until somebody is one.
        #expect(try await newsmakers.collections().map(\.kind) == [.builtIn(.newsmakers)])
    }

    @Test("The newsmakers square answers no articles, since it opens on people")
    func directoryHoldsNoArticles() async throws {
        try await article("Une rencontre", saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()

        #expect(try await articles.summaries(in: .builtIn(.newsmakers)).isEmpty)
    }

    @Test("The squares reach the collections page in the order of the page")
    func order() async throws {
        try await articles(Newsmaker.leastArticles, saying: "Donald Trump a parlé mardi soir.")
        try await readEverything()
        try await newsmakers.setFavourite("Donald Trump", true)

        let page = try await collections.builtIn().map(\.kind)
        let favourites = page.firstIndex(of: .builtIn(.favouriteNewsmakers))
        let directory = page.firstIndex(of: .builtIn(.newsmakers))

        // The judgement stands with the other favourites, and the directory
        // stands last, after the writers'.
        #expect(favourites != nil && directory != nil)
        #expect(favourites! < directory!)
        #expect(directory == page.count - 1)
    }

    // MARK: - What travels

    @Test("A record is named after the person, so two devices write one record between them")
    func recordNames() {
        let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName)
        let record = SyncRecords.record(forFavouriteNewsmaker: "Donald Trump", in: zone)

        #expect(record.recordID.recordName == SyncRecords.name(forFavouriteNewsmaker: "Donald Trump"))
        #expect(SyncRecords.favouriteNewsmaker(from: record) == "Donald Trump")
        // A prefix of its own : the same name may be a writer the reader
        // follows and somebody they read about, and those are two decisions.
        #expect(
            SyncRecords.name(forFavouriteNewsmaker: "Donald Trump")
                != SyncRecords.name(forFavouriteAuthor: "Donald Trump")
        )
        #expect(
            SyncRecords.name(forNotifiedNewsmaker: "Donald Trump")
                != SyncRecords.name(forFavouriteNewsmaker: "Donald Trump")
        )
    }

    @Test("A favourite reaches the other device, and the `no` travels with it")
    func travels() async throws {
        let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName)
        let payload = SyncPayload(database, zone: zone)

        _ = try await payload.apply([SyncRecords.record(forFavouriteNewsmaker: "Emmanuel Macron", in: zone)])
        // Nobody here has named them, and the decision is kept all the same.
        #expect(try await newsmakers.favourites() == ["Emmanuel Macron"])

        _ = try await payload.apply(deletions: [SyncRecords.name(forFavouriteNewsmaker: "Emmanuel Macron")])
        #expect(try await newsmakers.favourites().isEmpty)
    }

    @Test("What this device would say holds the people the reader singled out")
    func everything() async throws {
        try await newsmakers.setFavourite("Emmanuel Macron", true)
        try await newsmakers.setNotifies("Donald Trump", true)

        let zone = CKRecordZone.ID(zoneName: SyncRecords.zoneName)
        let names = Set(try await SyncPayload(database, zone: zone).everything().map(\.recordID.recordName))

        #expect(names.contains(SyncRecords.name(forFavouriteNewsmaker: "Emmanuel Macron")))
        #expect(names.contains(SyncRecords.name(forNotifiedNewsmaker: "Donald Trump")))
    }
}
