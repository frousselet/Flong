//
//  ArticleExtractor.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Pulls the article out of a page that is mostly not the article.
///
/// Most feeds serve a standfirst and a link, so the reader gets two sentences
/// and a trip to a browser. The page at the end of that link holds the article,
/// wrapped in navigation, a masthead, a sidebar, share buttons, related links
/// and a footer.
///
/// **What it looks for.** The page's own markup first : an `<article>`, an
/// `itemprop="articleBody"`, a `role="main"`. A publisher who says where the
/// article is has said it better than any heuristic could guess. Failing that,
/// the block of the page whose paragraphs hold the most text that is not
/// links : a menu is short lines that are all links, a sidebar is a list of
/// headlines, and an article is prose.
///
/// **What it drops.** Everything a reader skips : navigation, asides, forms,
/// share bars, related-article lists, comments. Judged by the element's kind,
/// by what the publisher called it, and by link density, since a paragraph made
/// mostly of links is not a paragraph.
///
/// What comes out goes through ``HTMLSanitizer`` like anything else, so it is
/// resolved against the article's own address, vetted, and reduced to the same
/// whitelist as a feed's own markup. Nothing here trusts the page.
nonisolated enum ArticleExtractor {
    /// Under this many characters of prose, what was found is not an article.
    ///
    /// A page that answers with two hundred characters has given a teaser, a
    /// consent wall or an error, and the feed's own summary is better than any
    /// of those.
    static let minimumCharacters = 400

    /// Above this share of link text, a block is a menu rather than prose.
    static let maximumLinkDensity = 0.5

    /// Elements that are never the article.
    static let furniture: Set<String> = [
        "nav", "aside", "header", "footer", "form", "button", "input", "select",
        "script", "style", "noscript", "iframe", "svg", "canvas", "template",
    ]

    /// What a publisher calls the parts of a page that are not the article.
    ///
    /// Matched against `class` and `id`, folded, as whole words : `share` must
    /// not take `shareholders`, and a class list is words.
    static let noise: Set<String> = [
        "nav", "navigation", "menu", "sidebar", "aside", "banner", "masthead",
        "share", "sharing", "social", "related", "recommended", "recirculation",
        "comment", "comments", "disqus", "newsletter", "subscribe", "subscription",
        "advert", "advertisement", "ads", "promo", "sponsored", "paywall",
        "cookie", "consent", "breadcrumb", "pagination", "tags", "byline",
        "footer", "header", "toolbar", "widget", "popup", "modal", "overlay",
    ]

    /// The article of a page, or `nil` when the page does not hold one.
    static func extract(_ html: String, from url: URL?) -> String? {
        let document = HTMLDocument(html)
        guard let body = document.firstElement(named: "body") ?? document.root.elements.first else { return nil }

        let candidates = [stated(in: body), scored(in: body)].compactMap { $0 }
        for candidate in candidates {
            let markup = serialize(candidate)
            let extracted = HTMLSanitizer.sanitize(markup, relativeTo: url)
            guard HTMLSanitizer.plainText(extracted).count >= minimumCharacters else { continue }
            return extracted
        }
        return nil
    }

    // MARK: - Finding the article

    /// What the page itself says is the article.
    static func stated(in body: HTMLElement) -> HTMLElement? {
        let candidates = body.descendants.filter { element in
            if element.name == "article" { return true }
            if element.attribute("itemprop")?.lowercased() == "articlebody" { return true }
            if element.attribute("role")?.lowercased() == "main" { return true }
            return element.name == "main"
        }

        // The one with the most prose, since a page may carry an `<article>`
        // per item in a list of related pieces.
        return candidates.max { prose(of: $0) < prose(of: $1) }
    }

    /// The block whose paragraphs hold the most prose.
    ///
    /// Each paragraph scores its own length, and hands that score to its parent
    /// and half of it to its grandparent : an article is not one long paragraph
    /// but a container full of them, and the container is what has to be found.
    static func scored(in body: HTMLElement) -> HTMLElement? {
        var scores: [ObjectIdentifier: Double] = [:]
        var elements: [ObjectIdentifier: HTMLElement] = [:]

        for paragraph in body.descendants where paragraph.name == "p" || paragraph.name == "pre" {
            let text = paragraph.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 25, linkDensity(of: paragraph) <= maximumLinkDensity else { continue }

            // Long paragraphs count for more, but not without limit : one
            // enormous block of terms and conditions is not an article.
            let length = Double(min(text.count, 1000)) / 100
            let commas = Double(text.filter { $0 == "," }.count) / 3
            let score: Double = 1 + length + commas

            var element = paragraph.parent
            var share = 1.0
            var depth = 0
            while let current = element, depth < 3 {
                if !isNoise(current) {
                    scores[ObjectIdentifier(current), default: 0] += score * share
                    elements[ObjectIdentifier(current)] = current
                }
                element = current.parent
                share /= 2
                depth += 1
            }
        }

        // A block made mostly of links scores well on a page of headlines, and
        // is a list of headlines.
        let best =
            scores
            .filter { linkDensity(of: elements[$0.key]!) <= maximumLinkDensity }
            .max { $0.value < $1.value }
        return best.flatMap { elements[$0.key] }
    }

    // MARK: - Judging a block

    /// How much of a block's text is inside links.
    static func linkDensity(of element: HTMLElement) -> Double {
        let total = element.textContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard total > 0 else { return 0 }

        let linked = element.descendants(named: "a")
            .reduce(0) { $0 + $1.textContent.trimmingCharacters(in: .whitespacesAndNewlines).count }
        return Double(linked) / Double(total)
    }

    /// The prose of a block : its text, less what is inside links.
    static func prose(of element: HTMLElement) -> Int {
        let total = element.textContent.trimmingCharacters(in: .whitespacesAndNewlines).count
        let linked = element.descendants(named: "a")
            .reduce(0) { $0 + $1.textContent.trimmingCharacters(in: .whitespacesAndNewlines).count }
        return max(total - linked, 0)
    }

    /// Whether the publisher has called this part of the page something a
    /// reader skips.
    static func isNoise(_ element: HTMLElement) -> Bool {
        if furniture.contains(element.name) { return true }

        let words =
            (element.classNames + [element.attribute("id") ?? ""])
            .flatMap { $0.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }

        return words.contains { noise.contains($0) }
    }

    // MARK: - Keeping what is left

    /// The block as markup, with the parts a reader skips left out.
    static func serialize(_ element: HTMLElement) -> String {
        var html = ""
        write(element, into: &html, isRoot: true)
        return html
    }

    private static func write(_ element: HTMLElement, into html: inout String, isRoot: Bool = false) {
        if !isRoot {
            guard !isNoise(element) else { return }

            // A list or a paragraph that is nearly all links is a menu wherever
            // it sits, whatever it is called.
            if ["ul", "ol", "p", "div", "section"].contains(element.name),
                element.textContent.count > 40,
                linkDensity(of: element) > maximumLinkDensity
            {
                return
            }
        }

        let attributes =
            element.attributes
            .map { " \($0.key)=\"\(HTMLEntities.escape($0.value))\"" }
            .sorted()
            .joined()

        if !isRoot { html += "<\(element.name)\(attributes)>" }
        for child in element.children {
            switch child {
            case .text(let text): html += HTMLEntities.escape(text)
            case .element(let child): write(child, into: &html)
            }
        }
        if !isRoot { html += "</\(element.name)>" }
    }
}
