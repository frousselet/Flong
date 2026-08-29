//
//  JSONFeedParser.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads JSON Feed 1.0 and 1.1.
///
/// The document is walked as plain values rather than decoded into types :
/// publishers write a number where the format says string often enough that a
/// strict decoder would refuse whole feeds over one field nobody reads.
nonisolated enum JSONFeedParser {
    static func parse(_ data: Data, url: URL) throws -> ParsedFeed {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeedParserError.unreadable
        }
        guard let version = root["version"] as? String, version.contains("jsonfeed.org") else {
            throw FeedParserError.notAFeed
        }

        var feed = ParsedFeed(format: .jsonFeed)
        feed.title = string(root["title"]).map(HTMLSanitizer.plainText)
        feed.siteURL = address(root["home_page_url"]) ?? url
        feed.iconURL = address(root["icon"]) ?? address(root["favicon"])
        feed.language = string(root["language"])
        feed.items = (root["items"] as? [[String: Any]] ?? []).compactMap(item)

        return feed
    }

    private static func item(_ object: [String: Any]) -> ParsedItem? {
        var item = ParsedItem()

        item.guid = string(object["id"])
        item.url = address(object["url"]) ?? address(object["external_url"])
        item.title = string(object["title"]).map(HTMLSanitizer.plainText)
        item.summaryHTML = string(object["summary"]).map(HTMLEntities.escape)
        item.language = string(object["language"])

        if let html = string(object["content_html"]) {
            item.contentHTML = html
        } else if let text = string(object["content_text"]) {
            item.contentHTML = HTMLEntities.escape(text)
        }

        item.publishedAt = string(object["date_published"]).flatMap(FeedDates.date(from:))
        item.updatedAt = string(object["date_modified"]).flatMap(FeedDates.date(from:))
        item.author = author(object)
        item.enclosures = (object["attachments"] as? [[String: Any]] ?? []).compactMap(enclosure)

        // 1.1 names both : `image` illustrates the article, `banner_image` runs
        // above it. Either is the article's picture.
        item.imageURL = address(object["image"]) ?? address(object["banner_image"])

        guard item.identity != nil else { return nil }
        return item
    }

    /// 1.1 states `authors`, 1.0 stated `author`, and feeds in the field carry
    /// either.
    private static func author(_ object: [String: Any]) -> String? {
        if let authors = object["authors"] as? [[String: Any]], let name = string(authors.first?["name"]) {
            return name
        }
        if let author = object["author"] as? [String: Any] {
            return string(author["name"])
        }
        return string(object["author"])
    }

    private static func enclosure(_ object: [String: Any]) -> Enclosure? {
        guard let url = address(object["url"]) else { return nil }
        return Enclosure(
            url: url,
            type: string(object["mime_type"]),
            length: (object["size_in_bytes"] as? NSNumber)?.intValue
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func address(_ value: Any?) -> URL? {
        guard let text = string(value), let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }
}
