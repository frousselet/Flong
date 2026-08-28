//
//  GReaderItemID.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Conversions between the two forms an article identifier takes.
///
/// FreshRSS stores an article identifier as a decimal number, and publishes it
/// as `tag:google.com,2005:reader/item/` followed by that number in hexadecimal,
/// zero padded to sixteen digits (`str_pad(dechex($id), 16, '0', STR_PAD_LEFT)`
/// in `app/Models/Entry.php`).
///
/// `stream/contents` returns the long form while `stream/items/ids` returns the
/// decimal one, so a client mixing the two endpoints has to convert. `edit-tag`
/// accepts either, which is why Flong round-trips the long form untouched and
/// only needs these conversions when reconciling identifier lists.
nonisolated enum GReaderItemID {
    static let longFormPrefix = "tag:google.com,2005:reader/item/"

    /// Builds the long form from a decimal identifier.
    ///
    /// Negative identifiers are rendered as their two's complement over 64 bits,
    /// which is what `dechex` does on a 64 bit platform.
    static func longForm(fromDecimal decimal: Int) -> String {
        let unsigned = UInt64(bitPattern: Int64(decimal))
        let hexadecimal = String(unsigned, radix: 16)
        return longFormPrefix + String(repeating: "0", count: max(0, 16 - hexadecimal.count)) + hexadecimal
    }

    /// Reads a decimal identifier back from the long form, or from a bare
    /// hexadecimal string. Returns `nil` when the value is not hexadecimal.
    static func decimal(fromLongForm identifier: String) -> Int? {
        let hexadecimal =
            identifier.hasPrefix(longFormPrefix)
            ? String(identifier.dropFirst(longFormPrefix.count))
            : identifier
        guard !hexadecimal.isEmpty, let unsigned = UInt64(hexadecimal, radix: 16) else { return nil }
        return Int(Int64(bitPattern: unsigned))
    }
}
