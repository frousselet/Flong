//
//  HTMLSanitizer.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Rewrites feed HTML into the subset Flong is willing to display.
///
/// Section 10 of the specification asks for a strict whitelist applied before
/// storage : an element that is not on the list does not survive, and neither
/// does an attribute. A whitelist is the only policy that stays safe as the web
/// invents new ways to run code, since anything new is unknown and unknown is
/// refused.
///
/// Three things get particular treatment, because they are how a feed reaches
/// past the article :
///
/// - **Scripts, frames and forms** are dropped with everything inside them.
/// - **Tracking pixels**, the images sized to disappear, are dropped, so opening
///   an article does not tell the publisher who read it and when.
/// - **Addresses** are resolved against the article and kept only when they end
///   up as `http`, `https` or `mailto`. A `javascript:` link is not a link.
nonisolated enum HTMLSanitizer {
    /// What survives, and with which attributes.
    private static let allowed: [String: Set<String>] = [
        "a": ["href", "title"],
        "abbr": ["title"],
        "article": [], "aside": [], "b": [], "blockquote": ["cite"], "br": [],
        "caption": [], "cite": [], "code": [], "col": ["span"], "colgroup": ["span"],
        "dd": [], "del": ["datetime"], "div": [], "dl": [], "dt": [], "em": [],
        "figcaption": [], "figure": [], "footer": [],
        "h1": [], "h2": [], "h3": [], "h4": [], "h5": [], "h6": [], "header": [], "hr": [],
        "i": [], "img": ["src", "alt", "title", "width", "height"], "ins": ["datetime"],
        "li": ["value"], "main": [], "mark": [], "ol": ["start", "reversed", "type"], "p": [],
        "picture": [], "pre": [], "q": ["cite"], "rp": [], "rt": [], "ruby": [],
        "s": [], "section": [], "small": [], "source": ["src", "type"], "span": [],
        "strong": [], "sub": [], "summary": [], "sup": [],
        "table": [], "tbody": [], "td": ["colspan", "rowspan"], "tfoot": [],
        "th": ["colspan", "rowspan", "scope"], "thead": [], "time": ["datetime"], "tr": [],
        "u": [], "ul": [], "wbr": [],
        "audio": ["src", "controls"], "video": ["src", "controls", "poster", "width", "height"],
    ]

    /// Attributes any element may keep.
    private static let globalAttributes: Set<String> = ["lang", "dir"]

    /// Elements dropped along with everything they hold.
    ///
    /// Unwrapping these would keep the text of a script or the labels of a form,
    /// which is worse than losing them.
    private static let dropped: Set<String> = [
        "applet", "base", "button", "canvas", "embed", "form", "frame", "frameset", "head",
        "iframe", "input", "link", "map", "math", "meta", "noscript", "object", "option",
        "param", "script", "select", "style", "svg", "template", "textarea", "title",
    ]

    /// Attributes holding an address, which is checked rather than trusted.
    private static let addressAttributes: Set<String> = ["href", "src", "cite", "poster"]

    private static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Sanitizes a fragment of feed HTML.
    ///
    /// `baseURL` is the address of the article, used to turn the relative links
    /// a feed serves into ones that work outside their site.
    static func sanitize(_ html: String, relativeTo baseURL: URL? = nil) -> String {
        var result = ""
        for node in HTMLDocument(html).root.children {
            serialize(node, relativeTo: baseURL, into: &result)
        }
        return result
    }

    // MARK: - Serializing

    private static func serialize(_ node: HTMLNode, relativeTo baseURL: URL?, into html: inout String) {
        switch node {
        case .text(let text):
            html += HTMLEntities.escape(text)

        case .element(let element):
            guard !dropped.contains(element.name) else { return }

            guard let permitted = allowed[element.name] else {
                // An element nobody knows is not a reason to lose its text.
                serializeChildren(of: element, relativeTo: baseURL, into: &html)
                return
            }

            let attributes = self.attributes(of: element, allowing: permitted, relativeTo: baseURL)

            if element.name == "img", attributes["src"] == nil { return }
            if isTrackingPixel(element) { return }
            if element.name == "a", attributes["href"] == nil {
                serializeChildren(of: element, relativeTo: baseURL, into: &html)
                return
            }

            html += "<" + element.name
            for name in attributes.keys.sorted() {
                html += " \(name)=\"\(HTMLEntities.escapeAttribute(attributes[name] ?? ""))\""
            }
            html += ">"

            guard !HTMLTokenizer.voidElements.contains(element.name) else { return }
            serializeChildren(of: element, relativeTo: baseURL, into: &html)
            html += "</\(element.name)>"
        }
    }

    private static func serializeChildren(of element: HTMLElement, relativeTo baseURL: URL?, into html: inout String) {
        for child in element.children {
            serialize(child, relativeTo: baseURL, into: &html)
        }
    }

    private static func attributes(
        of element: HTMLElement,
        allowing permitted: Set<String>,
        relativeTo baseURL: URL?
    ) -> [String: String] {
        var kept: [String: String] = [:]

        for (name, value) in element.attributes where permitted.contains(name) || globalAttributes.contains(name) {
            guard !value.isEmpty || name == "alt" else { continue }

            if addressAttributes.contains(name) {
                guard let address = self.address(value, relativeTo: baseURL) else { continue }
                kept[name] = address
            } else {
                kept[name] = value
            }
        }

        // A link out of the article opens elsewhere, and elsewhere is not
        // entitled to a handle on where it came from.
        if element.name == "a", kept["href"] != nil {
            kept["rel"] = "noopener noreferrer"
        }
        return kept
    }

    /// An address resolved and vetted, or `nil` when it is not one Flong follows.
    private static func address(_ value: String, relativeTo baseURL: URL?) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard allowedSchemes.contains(scheme) else { return nil }
        return url.absoluteString
    }

    /// An image sized to be invisible is there to count readers, not to be seen.
    private static func isTrackingPixel(_ element: HTMLElement) -> Bool {
        guard element.name == "img" else { return false }
        for name in ["width", "height"] {
            guard let value = element.attribute(name), let size = Int(value.filter(\.isNumber)) else { continue }
            if size <= 1 { return true }
        }
        return false
    }

    // MARK: - Plain text

    /// The article as text, which is what an excerpt and, later, the index need.
    static func plainText(_ html: String) -> String {
        var text = ""
        appendText(of: HTMLDocument(html).root, to: &text)

        // Markup carries the layout ; once it is gone, runs of space and blank
        // lines are noise.
        let lines =
            text
            .components(separatedBy: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    /// Text of at most `limit` characters, cut on a word.
    static func excerpt(_ html: String, limit: Int = 300) -> String {
        let text = plainText(html).replacingOccurrences(of: "\n", with: " ")
        guard text.count > limit else { return text }

        let cut = text.prefix(limit)
        guard let space = cut.lastIndex(where: \.isWhitespace) else { return String(cut) }
        return String(cut[..<space])
    }

    private static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "div", "dd", "dl", "dt", "figcaption", "figure",
        "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav", "ol", "p",
        "pre", "section", "table", "tr", "ul",
    ]

    private static func appendText(of element: HTMLElement, to text: inout String) {
        for node in element.children {
            switch node {
            case .text(let content):
                text += content
            case .element(let child):
                guard !dropped.contains(child.name) else { continue }
                if child.name == "br" || blockElements.contains(child.name) { text += "\n" }
                appendText(of: child, to: &text)
                if blockElements.contains(child.name) { text += "\n" }
            }
        }
    }
}
