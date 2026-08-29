//
//  StoredRecord.swift
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

/// What every record of the store has in common.
///
/// Columns are snake_case in SQL and camelCase in Swift, and each record spells
/// the mapping out in its `CodingKeys`. An automatic conversion looks tempting
/// and is a trap : it turns `feed_id` back into `feedId`, never into `feedID`,
/// and an optional property then reads as `nil` without a word of complaint.
///
/// Every record is covered by a round trip test that fills each of its
/// properties, which is what catches a column named wrong.
nonisolated protocol StoredRecord: Codable, FetchableRecord, PersistableRecord, Sendable {}
