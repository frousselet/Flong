//
//  EntryBody.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

/// The text of an article, kept apart from its metadata.
///
/// Listing the stream reads `entry` alone, so the bodies, which are what weighs
/// in the store, never enter the query. The full-text index of M1 reads this
/// table as its external content.
nonisolated struct EntryBody: Identifiable, Hashable, StoredRecord {
    static let databaseTableName = "entry_body"

    enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case sanitizedHTML = "sanitized_html"
        case extractedHTML = "extracted_html"
        case plainText = "plain_text"
    }

    /// The article this body belongs to, and the primary key of the row.
    var entryID: UUID

    /// The feed body, sanitized against the whitelist before it was stored.
    var sanitizedHTML: String?
    /// The reader mode body, when extraction succeeded.
    var extractedHTML: String?
    /// Markup stripped and whitespace normalized, which is what gets indexed.
    var plainText: String?

    var id: UUID { entryID }

    init(entryID: UUID, sanitizedHTML: String? = nil, extractedHTML: String? = nil, plainText: String? = nil) {
        self.entryID = entryID
        self.sanitizedHTML = sanitizedHTML
        self.extractedHTML = extractedHTML
        self.plainText = plainText
    }
}
