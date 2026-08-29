//
//  Log.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import OSLog

/// Logging entry points, grouped by domain.
nonisolated enum Log {
    private static let subsystem = "com.rslt.Flong"

    static let fetch = Logger(subsystem: subsystem, category: "fetch")
    static let parse = Logger(subsystem: subsystem, category: "parse")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let index = Logger(subsystem: subsystem, category: "index")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let enrich = Logger(subsystem: subsystem, category: "enrich")
}
