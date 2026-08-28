//
//  GReaderStreamIDTests.swift
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

@Suite("GReader stream identifiers")
struct GReaderStreamIDTests {
    @Test("Selectors map to their wire identifier")
    func selectorValues() {
        #expect(GReaderStreamID.value(for: .all) == "user/-/state/com.google/reading-list")
        #expect(GReaderStreamID.value(for: .starred) == "user/-/state/com.google/starred")
        #expect(GReaderStreamID.value(for: .folder(id: "user/-/label/News")) == "user/-/label/News")
        #expect(GReaderStreamID.value(for: .feed(id: "feed/42")) == "feed/42")
    }

    @Test("State streams keep literal separators in the path")
    func statePathComponents() {
        #expect(GReaderStreamID.pathComponents(for: .all) == "user/-/state/com.google/reading-list")
        #expect(GReaderStreamID.pathComponents(for: .starred) == "user/-/state/com.google/starred")
    }

    /// The server splits the path on `/` and matches segment by segment, so
    /// escaping the whole identifier would make the route fail.
    @Test("Only the trailing segment of a folder path is escaped")
    func folderPathComponents() {
        #expect(GReaderStreamID.pathComponents(for: .folder(id: "user/-/label/News")) == "user/-/label/News")
        #expect(
            GReaderStreamID.pathComponents(for: .folder(id: "user/-/label/Tech news"))
                == "user/-/label/Tech%20news"
        )
        #expect(
            GReaderStreamID.pathComponents(for: .folder(id: "user/-/label/A/B"))
                == "user/-/label/A%2FB"
        )
    }

    @Test("Feeds are addressed by their numeric identifier")
    func feedPathComponents() {
        #expect(GReaderStreamID.pathComponents(for: .feed(id: "feed/42")) == "feed/42")
    }

    @Test("Prefixes are stripped back off")
    func prefixStripping() {
        #expect(GReaderStreamID.folderName(fromID: "user/-/label/News") == "News")
        #expect(GReaderStreamID.folderName(fromID: "feed/42") == nil)
        #expect(GReaderStreamID.feedIdentifier(fromID: "feed/42") == "42")
        #expect(GReaderStreamID.feedIdentifier(fromID: "user/-/label/News") == nil)
    }
}
