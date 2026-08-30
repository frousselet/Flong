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
        static let libraryItem = "LibraryItem"
        static let readState = "ReadState"
        static let catchUp = "CatchUp"
        static let collections = "Collections"
    }

    // MARK: - Names

    static func name(forFeed url: URL) -> String { "feed-" + digest(url.absoluteString) }

    static func name(forLibraryItemWithGUID guid: String, feedURL: URL?) -> String {
        "item-" + digest((feedURL?.absoluteString ?? "") + "\n" + guid)
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

    // MARK: - Library items

    /// A kept article, content and all.
    ///
    /// The text is compressed. An article is a few tens of kilobytes of markup
    /// and compresses to a fifth of that, which keeps a record well inside what
    /// CloudKit accepts and a first synchronization well inside what a phone
    /// wants to upload.
    /// The one record naming every collection the reader has made.
    ///
    /// One record for the lot, and not one apiece : a collection is a name, and
    /// a few dozen names are a field rather than a table. What it exists for is
    /// the empty one. Membership travels on the articles, so a collection with
    /// something in it would arrive anyway ; a collection made a moment ago and
    /// not yet filled would not, and it is the one the reader is most likely to
    /// be looking at.
    static func record(
        forCollections names: [String],
        dynamic: [String: String] = [:],
        in zone: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.collections,
            recordID: CKRecord.ID(recordName: "collections", zoneID: zone)
        )
        record["names"] = names
        // A dynamic collection travels as its description and never as what
        // answers it : that is the whole point of it, and it is what makes one
        // holding ten thousand articles cost the same as one holding none.
        record["dynamic"] = try? JSONEncoder().encode(dynamic)
        return record
    }

    static func collectionNames(from record: CKRecord) -> [String]? {
        guard record.recordType == RecordType.collections else { return nil }
        return record["names"] as? [String] ?? []
    }

    static func dynamicCollections(from record: CKRecord) -> [String: String] {
        guard record.recordType == RecordType.collections,
            let payload = record["dynamic"] as? Data,
            let described = try? JSONDecoder().decode([String: String].self, from: payload)
        else { return [:] }
        return described
    }

    static func record(for item: LibraryItem, collections: [String] = [], in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.libraryItem,
            recordID: CKRecord.ID(
                recordName: name(forLibraryItemWithGUID: item.guid, feedURL: item.feedURL),
                zoneID: zone
            )
        )
        record["guid"] = item.guid
        record["feedURL"] = item.feedURL?.absoluteString
        record["feedTitle"] = item.feedTitle
        record["url"] = item.url?.absoluteString
        record["title"] = item.title
        record["author"] = item.author
        record["language"] = item.language
        record["publishedAt"] = item.publishedAt
        record["promotedAt"] = item.promotedAt
        // Why it was kept travels with it. A favourite that arrived on another
        // device as merely kept would be a favourite the reader has to make
        // again, on every device but the one they made it on.
        record["starredAt"] = item.starredAt
        record["annotation"] = item.annotation
        // Which collections it is in, on the article itself : a membership is
        // a fact about one article, and a record apiece would be one record per
        // filing in a budget that has none to spare.
        record["collections"] = collections
        record["contentHTML"] = compressed(item.contentHTML)
        record["plainText"] = compressed(item.plainText)

        // A vector travels with the pair that says what it can be compared to.
        // Section 14 is emphatic : a vector without them is not a vector, it is
        // five hundred numbers.
        record["vector"] = item.vector
        record["vectorModel"] = item.vectorModel
        record["vectorRevision"] = item.vectorRevision
        return record
    }

    /// Which collections a kept article says it is in.
    static func collections(from record: CKRecord) -> [String] {
        record["collections"] as? [String] ?? []
    }

    static func libraryItem(from record: CKRecord) -> LibraryItem? {
        guard record.recordType == RecordType.libraryItem, let guid = record["guid"] as? String else { return nil }

        var item = LibraryItem(
            feedURL: (record["feedURL"] as? String).flatMap(URL.init(string:)),
            feedTitle: record["feedTitle"] as? String,
            guid: guid,
            url: (record["url"] as? String).flatMap(URL.init(string:)),
            title: record["title"] as? String ?? "",
            author: record["author"] as? String,
            language: record["language"] as? String,
            publishedAt: record["publishedAt"] as? Date,
            promotedAt: record["promotedAt"] as? Date ?? Date(),
            contentHTML: expanded(record["contentHTML"] as? Data),
            plainText: expanded(record["plainText"] as? Data),
            annotation: record["annotation"] as? String
        )

        item.starredAt = record["starredAt"] as? Date
        item.vector = record["vector"] as? Data
        item.vectorModel = record["vectorModel"] as? String
        item.vectorRevision = record["vectorRevision"] as? String
        return item
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
