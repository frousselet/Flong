//
//  Fixtures.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The corpus of real feeds, malformed ones included, that section 22 of the
/// specification asks for.
///
/// Files are read from the source tree rather than from the test bundle, so
/// adding one to `FlongTests/Fixtures` is all it takes for a suite to use it.
nonisolated enum Fixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures")

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: path))
    }

    static func text(_ path: String) throws -> String {
        String(decoding: try data(path), as: UTF8.self)
    }
}

/// A box a `@Sendable` callback may write to from wherever it is called.
///
/// The progress and phase callbacks are `@Sendable` and synchronous by design,
/// so a test that wants to know what they said needs somewhere to put it that
/// does not depend on which executor called them.
nonisolated final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func write(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}

nonisolated extension Locked {
    func append<Element>(_ element: Element) where Value == [Element] {
        write { $0.append(element) }
    }
}
