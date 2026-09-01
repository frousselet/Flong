//
//  XMLFeedParser.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads RSS and Atom, which are close enough to share a parser.
///
/// RSS 0.9x, RSS 2.0, RSS 1.0 over RDF and Atom 1.0 differ in their element
/// names and in almost nothing else, and a feed routinely mixes them : an Atom
/// link inside an RSS channel, a Dublin Core date inside an Atom entry, a
/// content module carrying the body RSS has no element for. Matching on the
/// local name and the namespace, rather than on a declared format, is what makes
/// all of that readable.
nonisolated final class XMLFeedParser: NSObject, XMLParserDelegate {
    private enum Namespace {
        static let atom = "http://www.w3.org/2005/Atom"
        static let rss10 = "http://purl.org/rss/1.0/"
        static let content = "http://purl.org/rss/1.0/modules/content/"
        static let dublinCore = "http://purl.org/dc/elements/1.1/"
        static let media = "http://search.yahoo.com/mrss/"
        static let itunes = "http://www.itunes.com/dtds/podcast-1.0.dtd"
    }

    private var feed: ParsedFeed?
    private var item: ParsedItem?
    private var stack: [(name: String, namespace: String?)] = []
    private var text = ""

    /// The depth inside an Atom `content type="xhtml"`, whose markup is rebuilt
    /// rather than read as elements.
    private var capturedDepth: Int?
    private var captured = ""

    private var isPermaLink = true
    private var isNotAFeed = false

    static func parse(_ data: Data, url: URL) throws -> ParsedFeed {
        if let feed = try? run(data, url: url) { return feed }
        return try run(XMLRepair.repaired(data), url: url)
    }

    private static func run(_ data: Data, url: URL) throws -> ParsedFeed {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false

        let delegate = XMLFeedParser()
        parser.delegate = delegate

        let parsed = parser.parse()
        if delegate.isNotAFeed { throw FeedParserError.notAFeed }
        guard var feed = delegate.feed else {
            throw parsed ? FeedParserError.notAFeed : FeedParserError.unreadable
        }

        // A feed that stops halfway still holds the articles it got through, and
        // half a refresh beats none.
        guard parsed || !feed.items.isEmpty else { throw FeedParserError.unreadable }

        feed.siteURL = feed.siteURL ?? url

        // A feed states its icon as often relatively as absolutely, and a
        // relative address handed to a network is an address nothing can
        // fetch. Resolved against the feed, and dropped when it is not
        // something to ask a server for.
        feed.iconURL = feed.iconURL.flatMap { HTTPURL.resolved($0, against: url) }
        return feed
    }

    // MARK: - Elements

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.lowercased()

        if capturedDepth != nil {
            captured += markup(for: name, attributes: attributes)
            capturedDepth? += 1
            return
        }

        if feed == nil {
            guard let format = format(of: name, namespace: namespaceURI) else {
                isNotAFeed = true
                parser.abortParsing()
                return
            }
            feed = ParsedFeed(format: format)
            // Namespace processing reports `xml:lang` under either spelling
            // depending on how the document declares the prefix.
            if let language = attributes["lang"] ?? attributes["xml:lang"] {
                feed?.language = language
            }
        }

        stack.append((name, namespaceURI))
        text = ""

        switch (name, namespaceURI) {
        case ("item", _), ("entry", Namespace.atom):
            item = ParsedItem()

        case ("guid", _):
            isPermaLink = attributes["isPermaLink"] != "false"

        case ("link", Namespace.atom),
            ("link", nil) where namespaceURI == nil && feed?.format == .atom:
            link(attributes)

        case ("enclosure", _):
            addEnclosure(address: attributes["url"], type: attributes["type"], length: attributes["length"])

        // A thumbnail is the article's picture, not a file attached to it :
        // counting it as an enclosure would put a media badge on every article
        // of a feed that simply illustrates its headlines.
        case ("thumbnail", Namespace.media):
            setCover(attributes["url"])

        case ("content", Namespace.media):
            addEnclosure(address: attributes["url"], type: attributes["type"], length: attributes["fileSize"])
            if attributes["medium"] == "image" || attributes["type"]?.hasPrefix("image/") == true {
                setCover(attributes["url"])
            }

        case ("image", Namespace.itunes):
            setCover(attributes["href"])

        case ("content", Namespace.atom) where attributes["type"] == "xhtml":
            capturedDepth = 0
            captured = ""

        case ("content", Namespace.atom):
            contentType = attributes["type"]

        default:
            break
        }
    }

    private var contentType: String?

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = elementName.lowercased()

        if let depth = capturedDepth {
            if depth == 0, name == "content" {
                item?.contentHTML = captured
                capturedDepth = nil
                captured = ""
            } else {
                captured += "</\(name)>"
                capturedDepth = depth - 1
            }
            return
        }

        guard !stack.isEmpty else { return }
        stack.removeLast()

        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        switch (name, namespaceURI) {
        case ("item", _), ("entry", Namespace.atom):
            finishItem()
        default:
            assign(value, to: name, namespace: namespaceURI)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturedDepth != nil {
            captured += HTMLEntities.escape(string)
        } else {
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA cdata: Data) {
        // A body served as CDATA never reaches foundCharacters, and that is
        // where most RSS descriptions live.
        let block = String(decoding: cdata, as: UTF8.self)
        if capturedDepth != nil {
            captured += block
        } else {
            text += block
        }
    }

    // MARK: - Assigning

    private func assign(_ value: String, to name: String, namespace: String?) {
        let parent = stack.last?.name

        if item != nil {
            assignToItem(value, name: name, namespace: namespace, parent: parent)
        } else {
            assignToFeed(value, name: name, namespace: namespace, parent: parent)
        }
    }

    private func assignToItem(_ value: String, name: String, namespace: String?, parent: String?) {
        guard !value.isEmpty else { return }

        switch (name, namespace) {
        case ("title", _):
            item?.title = HTMLSanitizer.plainText(value)

        case ("link", _) where namespace != Namespace.atom:
            item?.url = URL(string: value)

        case ("guid", _):
            item?.guid = value
            // A permalink guid doubles as the article address, which is how
            // plenty of feeds spell a link they never wrote down. An Atom id
            // never does : it is a URN as often as not.
            if isPermaLink, item?.url == nil, let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
                item?.url = url
            }

        case ("id", Namespace.atom):
            item?.guid = value

        case ("description", _), ("summary", _):
            item?.summaryHTML = value

        case ("encoded", Namespace.content):
            item?.contentHTML = value

        case ("content", Namespace.atom):
            item?.contentHTML = contentType == "text" ? HTMLEntities.escape(value) : value
            contentType = nil

        case ("pubdate", _), ("published", _), ("issued", _), ("date", Namespace.dublinCore):
            item?.publishedAt = FeedDates.date(from: value)

        case ("updated", _), ("modified", _):
            item?.updatedAt = FeedDates.date(from: value)

        case ("creator", Namespace.dublinCore):
            item?.author = HTMLSanitizer.plainText(value)

        // **RSS 2.0 defines this one as an address**, and its own example is
        // `lawyer@boyer.net (Lawyer Boyer)`, where Dublin Core's creator and
        // Atom's name are names. A feed carrying both is ordinary, and which
        // of the two the parser met last is no reason to prefer it : the
        // address answers only where nothing has named anybody. What is left of
        // it once ``Author`` has had it is the person in the brackets, or
        // nobody at all.
        case ("author", _) where parent != "author" && item?.author == nil:
            item?.author = HTMLSanitizer.plainText(value)

        // Through the same door as the other two : an Atom name is a name, and
        // it used to be the one byline no publisher's markup was taken out of.
        case ("name", _) where parent == "author":
            item?.author = HTMLSanitizer.plainText(value)

        case ("lang", _):
            item?.language = value

        default:
            break
        }
    }

    private func assignToFeed(_ value: String, name: String, namespace: String?, parent: String?) {
        guard !value.isEmpty else { return }

        // An RSS image block repeats title, link and url, and none of them
        // describe the feed.
        let isImage = parent == "image"

        switch (name, namespace) {
        case ("title", _) where !isImage:
            feed?.title = HTMLSanitizer.plainText(value)

        case ("link", _) where !isImage && namespace != Namespace.atom:
            feed?.siteURL = URL(string: value)

        case ("language", _), ("lang", _):
            feed?.language = value

        case ("url", _) where isImage, ("icon", Namespace.atom), ("logo", Namespace.atom):
            // Kept as stated : `run` resolves it against the feed, which is
            // the only place that knows where the feed was.
            feed?.iconURL = URL(string: value)

        case ("updated", _), ("lastbuilddate", _), ("pubdate", _):
            feed?.updatedAt = FeedDates.date(from: value)

        default:
            break
        }
    }

    private func link(_ attributes: [String: String]) {
        guard let href = attributes["href"], let url = URL(string: href) else { return }
        let relation = attributes["rel"] ?? "alternate"

        switch relation {
        case "alternate":
            let type = attributes["type"]
            guard type == nil || type?.contains("html") == true else { return }
            if item != nil {
                if item?.url == nil { item?.url = url }
            } else if feed?.siteURL == nil {
                feed?.siteURL = url
            }

        case "enclosure":
            addEnclosure(address: href, type: attributes["type"], length: attributes["length"])

        default:
            break
        }
    }

    /// The first statement wins : a feed that carries both a thumbnail and a
    /// full picture states the thumbnail first, and either is better than none.
    private func setCover(_ address: String?) {
        guard item != nil, item?.imageURL == nil else { return }
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        item?.imageURL = url
    }

    private func addEnclosure(address: String?, type: String?, length: String?) {
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        let enclosure = Enclosure(url: url, type: type, length: length.flatMap(Int.init))

        if item != nil {
            guard item?.enclosures.contains(where: { $0.url == url }) != true else { return }
            item?.enclosures.append(enclosure)
        }
    }

    private func finishItem() {
        guard var item else { return }
        self.item = nil

        // A feed that dates nothing at the item level still dates its channel,
        // and an article with no date at all sorts on the day it arrived.
        if item.publishedAt == nil { item.publishedAt = item.updatedAt }
        guard item.identity != nil else { return }
        feed?.items.append(item)
    }

    // MARK: - Shapes

    private func format(of name: String, namespace: String?) -> FeedFormat? {
        switch (name, namespace) {
        case ("rss", _), ("rdf", _): .rss
        case ("feed", Namespace.atom), ("feed", nil): .atom
        default: nil
        }
    }

    /// Rebuilds the markup of an element being captured.
    private func markup(for name: String, attributes: [String: String]) -> String {
        let written =
            attributes
            .sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(HTMLEntities.escapeAttribute($0.value))\"" }
            .joined()
        return "<\(name)\(written)>"
    }
}
