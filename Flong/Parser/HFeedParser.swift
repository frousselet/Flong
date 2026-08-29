//
//  HFeedParser.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads an h-feed, the microformats2 markup a page carries in its own HTML.
///
/// There is no separate document to fetch : the page is the feed. Only the
/// properties an article needs are read, and a page that marks none of them is
/// not treated as a feed at all.
nonisolated enum HFeedParser {
    static func parse(_ data: Data, url: URL) throws -> ParsedFeed {
        let html = String(decoding: data, as: UTF8.self)
        return try parse(html, url: url)
    }

    static func parse(_ html: String, url: URL) throws -> ParsedFeed {
        let document = HTMLDocument(html)
        let entries = document.elements(withClass: "h-entry")
        guard !entries.isEmpty else { throw FeedParserError.notAFeed }

        var feed = ParsedFeed(format: .hFeed)
        feed.siteURL = url
        feed.title = document.firstElement(named: "title")?.textContent.trimmed
        feed.language = document.firstElement(named: "html")?.attribute("lang")

        if let container = document.elements(withClass: "h-feed").first,
            let name = property(of: container, "p-name")
        {
            feed.title = name
        }

        feed.items = entries.compactMap { entry(from: $0, relativeTo: url) }
        return feed
    }

    private static func entry(from element: HTMLElement, relativeTo base: URL) -> ParsedItem? {
        var item = ParsedItem()

        item.title = property(of: element, "p-name")
        item.summaryHTML = property(of: element, "p-summary").map(HTMLEntities.escape)
        item.url = address(of: element, "u-url", relativeTo: base)
        item.guid = property(of: element, "u-uid") ?? item.url?.absoluteString
        item.publishedAt = date(of: element, "dt-published")
        item.updatedAt = date(of: element, "dt-updated")

        if let content = first(in: element, withClass: "e-content") {
            item.contentHTML = content.innerHTML
            if item.title == nil {
                item.title = content.textContent.trimmed.map { String($0.prefix(120)) }
            }
        }

        item.imageURL = photo(of: element, relativeTo: base)

        if let author = first(in: element, withClass: "p-author") {
            item.author = property(of: author, "p-name") ?? author.textContent.trimmed
        }

        guard item.identity != nil else { return nil }
        return item
    }

    /// The picture the entry carries, which is not its author's face.
    ///
    /// `u-photo` is also how an `h-card` states an avatar, and an entry that
    /// names its author carries one inside itself.
    private static func photo(of element: HTMLElement, relativeTo base: URL) -> URL? {
        let candidates = element.descendants.filter {
            $0.classNames.contains("u-photo")
                && !isInsideAnotherEntry($0, below: element)
                && !isInside($0, withClass: "h-card", below: element)
        }
        let value = candidates.lazy.compactMap { $0.attribute("src") ?? $0.attribute("href") }.first
        guard let value, let url = URL(string: value, relativeTo: base)?.absoluteURL else { return nil }
        return url
    }

    /// Whether an element sits below an ancestor carrying that class.
    private static func isInside(
        _ element: HTMLElement,
        withClass className: String,
        below root: HTMLElement
    ) -> Bool {
        var parent = element.parent
        while let current = parent, current !== root {
            if current.classNames.contains(className) { return true }
            parent = current.parent
        }
        return false
    }

    /// The first element carrying that class, this one included, nested entries
    /// excluded.
    private static func first(in element: HTMLElement, withClass className: String) -> HTMLElement? {
        if element.classNames.contains(className) { return element }
        return element.descendants.first { candidate in
            candidate.classNames.contains(className) && !isInsideAnotherEntry(candidate, below: element)
        }
    }

    /// Whether a property belongs to an entry nested inside this one, which
    /// happens on a page listing comments below an article.
    private static func isInsideAnotherEntry(_ element: HTMLElement, below root: HTMLElement) -> Bool {
        var parent = element.parent
        while let current = parent, current !== root {
            if current.classNames.contains("h-entry") { return true }
            parent = current.parent
        }
        return false
    }

    /// The value of a text property, read the way microformats2 states it.
    private static func property(of element: HTMLElement, _ className: String) -> String? {
        guard let found = first(in: element, withClass: className) else { return nil }

        switch found.name {
        case "abbr", "link": return found.attribute("title")?.trimmed ?? found.textContent.trimmed
        case "img", "area": return found.attribute("alt")?.trimmed ?? found.textContent.trimmed
        default: return found.textContent.trimmed
        }
    }

    private static func address(of element: HTMLElement, _ className: String, relativeTo base: URL) -> URL? {
        guard let found = first(in: element, withClass: className) else { return nil }
        let value = found.attribute("href") ?? found.attribute("src") ?? found.textContent.trimmed
        guard let value, let url = URL(string: value, relativeTo: base)?.absoluteURL else { return nil }
        return url
    }

    private static func date(of element: HTMLElement, _ className: String) -> Date? {
        guard let found = first(in: element, withClass: className) else { return nil }
        let value = found.attribute("datetime") ?? found.attribute("title") ?? found.textContent.trimmed
        return value.flatMap(FeedDates.date(from:))
    }
}

nonisolated extension String {
    /// The string without its surrounding whitespace, or `nil` when nothing is left.
    fileprivate var trimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
