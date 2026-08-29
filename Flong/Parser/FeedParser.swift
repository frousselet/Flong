//
//  FeedParser.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads whatever a feed turns out to be.
///
/// The declared content type is a hint and nothing more : servers send RSS as
/// `text/plain`, JSON Feed as `text/html`, and Atom as anything at all. What the
/// bytes start with is the reliable signal, and every format is tried before a
/// document is declared not to be a feed.
nonisolated enum FeedParser {
    static func parse(_ data: Data, url: URL, contentType: String? = nil) throws -> ParsedFeed {
        var wasReadable = false

        for parser in order(for: data, contentType: contentType) {
            do {
                return try parser(data, url)
            } catch FeedParserError.notAFeed {
                // One format understood the bytes and found no feed in them,
                // which is a different answer from nobody understanding them.
                wasReadable = true
            } catch {
                continue
            }
        }

        throw wasReadable ? FeedParserError.notAFeed : FeedParserError.unreadable
    }

    private typealias Parse = (Data, URL) throws -> ParsedFeed

    /// The formats to try, likeliest first.
    private static func order(for data: Data, contentType: String?) -> [Parse] {
        let xml: Parse = XMLFeedParser.parse
        let json: Parse = JSONFeedParser.parse
        let hFeed: Parse = HFeedParser.parse

        let type = (contentType ?? "").lowercased()
        if type.contains("json") { return [json, xml, hFeed] }

        switch firstMeaningfulByte(of: data) {
        case UInt8(ascii: "{"), UInt8(ascii: "["): return [json, xml, hFeed]
        case UInt8(ascii: "<"): return [xml, hFeed, json]
        default: return [xml, json, hFeed]
        }
    }

    /// The first byte that is neither whitespace nor a byte order mark.
    private static func firstMeaningfulByte(of data: Data) -> UInt8? {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF]
        return data.prefix(64).first { !whitespace.contains($0) }
    }
}
