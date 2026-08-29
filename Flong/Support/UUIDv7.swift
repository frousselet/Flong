//
//  UUIDv7.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

nonisolated extension UUID {
    /// A version 7 identifier, as specified by RFC 9562.
    ///
    /// The first 48 bits hold the creation time in milliseconds since the epoch,
    /// so identifiers sort by creation order and rows land at the end of their
    /// index instead of scattering through it. Every technical key of the store
    /// is one of these.
    ///
    /// The remaining 74 bits are random, which keeps identifiers unguessable and
    /// makes a collision within one millisecond implausible.
    nonisolated static func v7(at date: Date = Date()) -> UUID {
        let milliseconds = UInt64((date.timeIntervalSince1970 * 1000).rounded(.down))
        var bytes = [UInt8](repeating: 0, count: 16)

        for index in 0..<6 {
            bytes[index] = UInt8((milliseconds >> (40 - 8 * UInt64(index))) & 0xFF)
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: .min ... .max)
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x70  // Version 7.
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant 10.

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    /// The creation time carried by a version 7 identifier, `nil` for any other version.
    nonisolated var v7Timestamp: Date? {
        let bytes = uuid
        guard bytes.6 & 0xF0 == 0x70 else { return nil }

        var milliseconds: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5] {
            milliseconds = (milliseconds << 8) | UInt64(byte)
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
