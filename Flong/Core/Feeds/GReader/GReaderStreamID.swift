//
//  GReaderStreamID.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Stream identifiers of the Google Reader API, as FreshRSS implements them.
///
/// Verified against `p/api/greader.php` and `app/Models/Entry.php` in FreshRSS
/// 1.29.1 : feeds are addressed by their numeric identifier, not by their URL,
/// and folders share the `user/-/label/` prefix with article labels.
nonisolated enum GReaderStreamID {
    static let readingList = "user/-/state/com.google/reading-list"
    static let starred = "user/-/state/com.google/starred"
    static let read = "user/-/state/com.google/read"

    static let labelPrefix = "user/-/label/"
    static let feedPrefix = "feed/"

    static func label(_ name: String) -> String { labelPrefix + name }
    static func feed(_ identifier: String) -> String { feedPrefix + identifier }

    /// "user/-/label/News" -> "News"
    static func folderName(fromID id: String) -> String? {
        guard id.hasPrefix(labelPrefix) else { return nil }
        return String(id.dropFirst(labelPrefix.count))
    }

    /// "feed/42" -> "42"
    static func feedIdentifier(fromID id: String) -> String? {
        guard id.hasPrefix(feedPrefix) else { return nil }
        return String(id.dropFirst(feedPrefix.count))
    }

    /// The identifier as it travels in a form field or a query item.
    static func value(for selector: StreamSelector) -> String {
        switch selector {
        case .all: readingList
        case .starred: starred
        case .folder(let id): id
        case .feed(let id): id
        }
    }

    /// The identifier as it travels inside the path of `stream/contents`.
    ///
    /// FreshRSS splits that path on `/` and matches the segments one by one, so
    /// the separators must stay literal and only the trailing name is escaped.
    /// Escaping the whole identifier as a single component makes the route fail.
    static func pathComponents(for selector: StreamSelector) -> String {
        switch selector {
        case .all, .starred:
            value(for: selector)
        case .folder(let id):
            labelPrefix + escape(folderName(fromID: id) ?? id)
        case .feed(let id):
            feedPrefix + escape(feedIdentifier(fromID: id) ?? id)
        }
    }

    /// Percent-encodes one path segment. `urlPathAllowed` lets `/` and `:`
    /// through, which would break the segment matching, so they are escaped too.
    static func escape(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .greaderPathSegment) ?? segment
    }
}

nonisolated extension CharacterSet {
    static let greaderPathSegment = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/:;=+&?#"))
}
