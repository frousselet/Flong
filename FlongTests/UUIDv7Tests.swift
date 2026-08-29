//
//  UUIDv7Tests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("UUIDv7")
struct UUIDv7Tests {
    @Test("The version and variant bits follow RFC 9562")
    func versionAndVariant() {
        for _ in 0..<100 {
            let bytes = UUID.v7().uuid
            #expect(bytes.6 & 0xF0 == 0x70)
            #expect(bytes.8 & 0xC0 == 0x80)
        }
    }

    @Test("The creation time survives the round trip")
    func timestampRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_756_000_000.123)
        let read = try #require(UUID.v7(at: date).v7Timestamp)
        #expect(abs(read.timeIntervalSince(date)) < 0.001)
    }

    @Test("Another version carries no creation time")
    func otherVersionsHaveNoTimestamp() {
        #expect(UUID().v7Timestamp == nil)
    }

    @Test("Identifiers created later sort after the earlier ones")
    func ordering() {
        let start = Date(timeIntervalSince1970: 1_756_000_000)
        let ids = (0..<50).map { UUID.v7(at: start.addingTimeInterval(Double($0) / 100)) }

        #expect(ids.sorted { $0.uuidString < $1.uuidString } == ids)
    }

    @Test("Two identifiers of the same millisecond still differ")
    func randomnessInsideAMillisecond() {
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        let ids = Set((0..<1000).map { _ in UUID.v7(at: date) })
        #expect(ids.count == 1000)
    }
}
