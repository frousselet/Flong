//
//  SyncRecords.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import CryptoKit
import Foundation

/// What travels between a reader's devices, and what it is called.
///
/// Every record name is **derived from what the record is about**, never from a
/// local identifier. Two devices that star the same article compute the same
/// name and write the same record, which is what turns two concurrent writes
/// into one row rather than two. A name derived from a local UUID would give
/// every device its own copy of everything.
nonisolated enum SyncRecords {
    /// The one zone. A custom zone rather than the default one, since only a
    /// custom zone can be fetched by change token and deleted whole.
    static let zoneName = "Flong"

    enum RecordType {
        static let feed = "Feed"
        static let mark = "Mark"
        static let readState = "ReadState"
        static let sourceName = "SourceName"
        static let catchUp = "CatchUp"
        static let collections = "Collections"
        static let favouriteAuthor = "FavouriteAuthor"
        /// What a shared collection is called, in the zone standing for it.
        static let sharedCollection = "SharedCollection"
        /// What one participant filed into a shared collection.
        static let sharedList = "SharedList"
    }

    // MARK: - A collection that is shared

    /// The zone one shared collection lives in.
    ///
    /// **A zone of its own, and never the one everything else is in.** A
    /// `CKShare` reaches a single zone, and a zone holds a single zone-wide
    /// share, so a second shared collection is a second zone. Sharing
    /// ``zoneName`` instead would hand a participant every feed, every mark,
    /// every read state and the whole stream in one gesture.
    ///
    /// Named after an identifier of this device's making rather than after the
    /// collection : a reader renames a collection, and two readers may name
    /// theirs the same thing, while a zone name is fixed for the life of the
    /// zone and has to be unique in the database.
    static func zoneName(forSharedCollection id: UUID) -> String {
        "shared-" + id.uuidString.lowercased()
    }

    /// What the record naming a shared collection is called.
    ///
    /// One per zone, so a fixed name rather than a derived one : there is
    /// nothing to tell apart.
    static let sharedCollectionName = "collection"

    /// One participant's list in a shared collection, and one chunk of it.
    ///
    /// **Named after the person, so that each of them writes only their own.**
    /// Two participants filing at the same moment then touch two records and
    /// cannot collide, which is what removes conflict resolution from this
    /// entirely. Two devices of one participant work the same name out and
    /// rewrite one list between them rather than opening a second.
    static func name(forSharedListBy participant: CKRecord.ID, chunk: Int = 0) -> String {
        "list-" + digest(participant.recordName) + "-" + String(chunk)
    }

    /// What every chunk of one participant's list is named under.
    static func namePrefix(forSharedListBy participant: CKRecord.ID) -> String {
        "list-" + digest(participant.recordName) + "-"
    }

    /// Which participant's list a record belongs to, from its name alone.
    ///
    /// **The one thing a modification and a deletion have in common.** A record
    /// that arrives says who wrote it ; a record that is deleted arrives as an
    /// identifier and nothing else, and one participant taking everything out
    /// of a collection has to reach exactly their own rows and no one else's.
    /// The name is what answers that in both cases, so the name is what the
    /// store is keyed by.
    ///
    /// `nil` for a name that is not one of these, which is how a record of some
    /// other kind is left alone rather than read as an empty list.
    static func listKey(ofRecordNamed name: String) -> String? {
        guard name.hasPrefix("list-"), let last = name.lastIndex(of: "-"), last > name.startIndex else { return nil }
        let key = String(name[..<last]) + "-"
        return key == "list-" ? nil : key
    }

    // MARK: - Names

    static func name(forFeed url: URL) -> String { "feed-" + digest(url.absoluteString) }

    /// The name the reader gave one publisher.
    static func name(forSourceNamedDomain domain: String) -> String { "source-" + digest(domain) }

    /// One writer the reader singled out, named after the writer.
    ///
    /// Two devices that single out the same person compute the same name and
    /// write one record between them, and nothing has to be reconciled.
    static func name(forFavouriteAuthor author: String) -> String { "author-" + digest(author) }

    /// One marked article, named after the article and not after the device.
    ///
    /// The same pair on two devices gives the same name, so two readers of one
    /// account starring the same piece write one record between them.
    static func name(forMarkWithGUID guid: String, feedURL: URL?) -> String {
        "mark-" + digest((feedURL?.absoluteString ?? "") + "\n" + guid)
    }

    static func name(forReadStatePeriod period: String, kind: ReadStateKind) -> String {
        "read-\(kind.rawValue)-\(period)"
    }

    /// One feed, one day, one chunk of it.
    ///
    /// The chunk is what keeps a busy day inside a record. CloudKit takes about
    /// a megabyte of fields, and a day of a wire service carrying its articles
    /// whole goes past that : the day is cut into as many records as it needs,
    /// numbered from zero, and a day that fits is simply `-0`.
    static func name(forCatchUpFeed url: URL, day: String, chunk: Int = 0) -> String {
        namePrefix(forCatchUpFeed: url) + day + "-" + String(chunk)
    }

    /// What every block of one feed's stream is named under.
    ///
    /// A name is a digest and cannot be read backwards, so this is the only way
    /// back from a feed to the records carrying it : the days are not known
    /// once the articles have gone, and the number of chunks a day was cut into
    /// never was known anywhere but in the record names themselves.
    static func namePrefix(forCatchUpFeed url: URL) -> String {
        "catchup-" + digest(url.absoluteString) + "-"
    }

    /// The same record, carrying the tag the server expects.
    ///
    /// A record built from the store alone is a record the server has never
    /// seen, and CloudKit refuses one under a name it already holds :
    /// `record to insert already exists`. The tag lives in the system fields
    /// of the record the server handed back, so a save starts from those and
    /// copies the values over.
    ///
    /// An archive that will not decode is treated as no archive : the save is
    /// refused once, the server hands the record back, and the tag is learned
    /// again.
    static func rebased(_ record: CKRecord, onto systemFields: Data?) -> CKRecord {
        guard let systemFields,
            let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields),
            let base = CKRecord(coder: coder)
        else { return record }

        coder.finishDecoding()
        guard base.recordID == record.recordID, base.recordType == record.recordType else { return record }

        for key in record.allKeys() {
            base[key] = record[key]
        }
        return base
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - A list that may be empty

    /// A list of names, written as data rather than as a list of strings.
    ///
    /// **CloudKit cannot create a field from an empty list.** It infers a
    /// field's type from the first record that carries it, and an empty list
    /// says nothing about what it would hold : the server answers `cannot use
    /// an empty list to initialize a new field` and refuses the whole batch,
    /// not just that record.
    ///
    /// This is the ordinary case, not an edge one. Starring an article files
    /// it in nothing, so the first mark a reader ever makes carries an empty
    /// list, and the first save of their life fails.
    ///
    /// **Leaving the field out is worse.** A field absent from a save keeps
    /// whatever the server already holds, so unfiling the last collection off
    /// an article would never travel : the other device would go on showing
    /// a filing the reader removed.
    ///
    /// Data has neither problem. It says `[]` in two bytes, its type is the
    /// same whatever it holds, and emptying it is a change like any other.
    static func data(for names: [String]) -> Data {
        (try? JSONEncoder().encode(names)) ?? Data("[]".utf8)
    }

    /// The names back out, taking what an earlier version left if that is all
    /// there is.
    ///
    /// A record written before this change carries the list and not the data.
    /// It is still on the server and it is still the reader's, so it is read
    /// rather than dropped ; the next write of that record moves it over.
    static func names(from record: CKRecord, _ key: String, orList list: String) -> [String] {
        if let payload = record[key] as? Data,
            let names = try? JSONDecoder().decode([String].self, from: payload)
        {
            return names
        }
        return record[list] as? [String] ?? []
    }

    // MARK: - Feeds

    /// What a subscription looks like on the wire.
    ///
    /// The health of a feed stays at home : the counters, the `ETag`, the
    /// quarantine and the observed interval are what *this* device knows about
    /// its own fetching, and telling another device about them would be telling
    /// it something untrue.
    static func record(for feed: Feed, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.feed,
            recordID: CKRecord.ID(recordName: name(forFeed: feed.url), zoneID: zone)
        )
        record["url"] = feed.url.absoluteString
        record["title"] = feed.title
        record["isFavourite"] = feed.isFavourite ? 1 : 0
        // Where it used to be served, so that a device holding it there moves
        // the row it already has. Without it the pair of a record under a new
        // name and a deletion under the old one is a removal followed by a
        // subscription, and the removal takes the articles.
        record["previousURL"] = feed.previousURL?.absoluteString
        record["siteURL"] = feed.siteURL?.absoluteString
        record["iconURL"] = feed.iconURL?.absoluteString
        record["createdAt"] = feed.createdAt
        return record
    }

    static func subscription(from record: CKRecord) -> Subscription? {
        guard record.recordType == RecordType.feed, let url = record["url"] as? String else { return nil }

        return try? Subscription(
            address: url,
            title: record["title"] as? String ?? "",
            siteURL: (record["siteURL"] as? String).flatMap(URL.init(string:)),
            iconURL: (record["iconURL"] as? String).flatMap(URL.init(string:))
        )
    }

    /// The address the source was served at before it moved, when it has.
    ///
    /// `nil` for a source that has always been where it is, and for a record
    /// written before a source could be moved at all.
    static func previousURL(from record: CKRecord) -> URL? {
        guard record.recordType == RecordType.feed else { return nil }
        return (record["previousURL"] as? String).flatMap(URL.init(string:))
    }

    /// Whether the record says the reader singled that source out.
    ///
    /// `nil` when the field is absent, which is what a record written before
    /// favourites existed looks like. Nothing said is not the same as no, and
    /// treating it as no would have the first device to read an old record
    /// unstar every source on every other one.
    static func isFavourite(from record: CKRecord) -> Bool? {
        (record["isFavourite"] as? Int).map { $0 == 1 }
    }

    // MARK: - The names of publishers

    /// What the reader calls one publisher.
    ///
    /// A record apiece, and only for the ones they actually named : the groups
    /// themselves are worked out from the addresses of the feeds, so there is
    /// nothing to send about the ones still called what they are. A reader
    /// naming a few dozen spends a few dozen records of the budget of
    /// section 7, where a record per group would spend one per publisher
    /// followed.
    static func record(for name: SourceName, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.sourceName,
            recordID: CKRecord.ID(recordName: self.name(forSourceNamedDomain: name.domain), zoneID: zone)
        )
        record["domain"] = name.domain
        record["name"] = name.name
        record["createdAt"] = name.createdAt
        return record
    }

    static func sourceName(from record: CKRecord) -> SourceName? {
        guard record.recordType == RecordType.sourceName,
            let domain = record["domain"] as? String,
            let name = record["name"] as? String,
            !domain.isEmpty, !name.isEmpty
        else { return nil }

        return SourceName(domain: domain, name: name, createdAt: record["createdAt"] as? Date ?? Date())
    }

    // MARK: - The writers the reader singled out

    /// One favourite author.
    ///
    /// **A record apiece, and only for the ones the reader singled out.** The
    /// writers themselves are worked out from the articles, so there is nothing
    /// to send about the thousands nobody has an opinion on. A reader who
    /// follows a few dozen bylines spends a few dozen records of the budget of
    /// section 7.
    ///
    /// **The record is the favourite, and its deletion is the `no`.** A field
    /// saying yes or no would need a record per writer ever considered ; here
    /// the presence of the record is the whole of the answer, which is why
    /// un-favouriting deletes it rather than rewriting it.
    static func record(forFavouriteAuthor author: String, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.favouriteAuthor,
            recordID: CKRecord.ID(recordName: name(forFavouriteAuthor: author), zoneID: zone)
        )
        record["name"] = author
        return record
    }

    static func favouriteAuthor(from record: CKRecord) -> String? {
        guard record.recordType == RecordType.favouriteAuthor,
            let name = record["name"] as? String,
            !name.isEmpty
        else { return nil }

        return name
    }

    // MARK: - The reader's marks

    /// What the reader said about one article.
    ///
    /// One record apiece, which is what the library's record was and what
    /// section 8 budgeted for : a reader marks a few thousand articles in
    /// years. See ``Mark`` for why a block per month, the shape read states
    /// take, is the wrong one here.
    ///
    /// The collections it is filed in ride along as a field. A filing costs a
    /// field on a record that exists anyway, and never a record of its own.
    static func record(for mark: Mark, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.mark,
            recordID: CKRecord.ID(
                recordName: name(forMarkWithGUID: mark.guid, feedURL: URL(string: mark.feedURL)),
                zoneID: zone
            )
        )
        record["feedURL"] = mark.feedURL
        record["guid"] = mark.guid
        record["isStarred"] = mark.isStarred ? 1 : 0
        record["annotation"] = mark.annotation
        record["filedIn"] = data(for: mark.collections)
        record["vector"] = mark.vector
        record["vectorModel"] = mark.vectorModel
        record["vectorRevision"] = mark.vectorRevision
        return record
    }

    static func mark(from record: CKRecord) -> Mark? {
        guard record.recordType == RecordType.mark,
            let feedURL = record["feedURL"] as? String,
            let guid = record["guid"] as? String
        else { return nil }

        return Mark(
            feedURL: feedURL,
            guid: guid,
            isStarred: (record["isStarred"] as? Int ?? 0) == 1,
            annotation: record["annotation"] as? String,
            collections: names(from: record, "filedIn", orList: "collections"),
            vector: record["vector"] as? Data,
            vectorModel: record["vectorModel"] as? String,
            vectorRevision: record["vectorRevision"] as? String
        )
    }

    // MARK: - Collections

    /// Every collection the reader has, as one record.
    ///
    /// One record for the lot, and not one apiece. What it exists for is the
    /// collection that carries no articles : a made one with something in it
    /// arrives on the articles themselves, and a dynamic one is nothing but a
    /// description, which is exactly what makes it cost the same whether it
    /// holds nothing or ten thousand.
    static func record(
        forCollections names: [String],
        dynamic: [String: String] = [:],
        in zone: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.collections,
            recordID: CKRecord.ID(recordName: "collections", zoneID: zone)
        )
        record["made"] = data(for: names)
        record["dynamic"] = try? JSONEncoder().encode(dynamic)
        return record
    }

    static func collectionNames(from record: CKRecord) -> [String]? {
        guard record.recordType == RecordType.collections else { return nil }
        return names(from: record, "made", orList: "names")
    }

    static func dynamicCollections(from record: CKRecord) -> [String: String] {
        guard record.recordType == RecordType.collections,
            let payload = record["dynamic"] as? Data,
            let described = try? JSONDecoder().decode([String: String].self, from: payload)
        else { return [:] }
        return described
    }

    // MARK: - Read states

    static func record(for block: ReadStateBlock, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.readState,
            recordID: CKRecord.ID(
                recordName: name(forReadStatePeriod: block.period, kind: block.kind),
                zoneID: zone
            )
        )
        record["period"] = block.period
        record["kind"] = block.kind.rawValue
        record["fingerprints"] = block.encoded()
        return record
    }

    static func readStateBlock(from record: CKRecord) -> ReadStateBlock? {
        guard record.recordType == RecordType.readState,
            let period = record["period"] as? String,
            let kind = (record["kind"] as? String).flatMap(ReadStateKind.init(rawValue:)),
            let fingerprints = record["fingerprints"] as? Data
        else { return nil }

        return ReadStateBlock.decode(fingerprints, period: period, kind: kind)
    }

    // MARK: - Bytes

    static func compressed(_ text: String?) -> Data? {
        guard let text, !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        guard let compressed = try? (data as NSData).compressed(using: .lzfse) as Data else { return data }
        return compressed.count < data.count ? compressed : data
    }

    static func expanded(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let expanded = try? (data as NSData).decompressed(using: .lzfse) as Data {
            return String(decoding: expanded, as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
