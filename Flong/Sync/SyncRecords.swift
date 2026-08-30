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
        static let catchUp = "CatchUp"
        static let collections = "Collections"
    }

    // MARK: - Names

    static func name(forFeed url: URL) -> String { "feed-" + digest(url.absoluteString) }

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
        "catchup-" + digest(url.absoluteString) + "-" + day + "-" + String(chunk)
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
        record["folder"] = feed.folder
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
            iconURL: (record["iconURL"] as? String).flatMap(URL.init(string:)),
            folder: record["folder"] as? String
        )
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
