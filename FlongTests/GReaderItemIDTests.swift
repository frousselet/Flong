//
//  GReaderItemIDTests.swift
//  FlongTests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("GReader article identifiers")
struct GReaderItemIDTests {
    @Test("The long form is the identifier in hexadecimal, padded to sixteen digits")
    func longFormPadding() {
        // 312840 == 0x4c608
        #expect(GReaderItemID.longForm(fromDecimal: 312_840) == "tag:google.com,2005:reader/item/000000000004c608")
        #expect(GReaderItemID.longForm(fromDecimal: 0) == "tag:google.com,2005:reader/item/0000000000000000")
    }

    /// The server renders a negative identifier as its two's complement over 64
    /// bits, so the padding must never truncate a full width value.
    @Test("Negative identifiers use the full sixty four bit width")
    func negativeIdentifiers() {
        #expect(GReaderItemID.longForm(fromDecimal: -1) == "tag:google.com,2005:reader/item/ffffffffffffffff")
        #expect(GReaderItemID.decimal(fromLongForm: "tag:google.com,2005:reader/item/ffffffffffffffff") == -1)
    }

    @Test("Both forms convert back into each other", arguments: [0, 1, 312_840, 1_755_000_000_000_000, -42])
    func roundTrip(identifier: Int) {
        let longForm = GReaderItemID.longForm(fromDecimal: identifier)
        #expect(GReaderItemID.decimal(fromLongForm: longForm) == identifier)
    }

    @Test("A bare hexadecimal string is accepted without the prefix")
    func bareHexadecimal() {
        #expect(GReaderItemID.decimal(fromLongForm: "000000000004c608") == 312_840)
    }

    @Test("Anything that is not hexadecimal is refused")
    func invalidInput() {
        #expect(GReaderItemID.decimal(fromLongForm: "") == nil)
        #expect(GReaderItemID.decimal(fromLongForm: "tag:google.com,2005:reader/item/") == nil)
        #expect(GReaderItemID.decimal(fromLongForm: "not-hexadecimal") == nil)
    }
}
