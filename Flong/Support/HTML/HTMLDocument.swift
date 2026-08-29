//
//  HTMLDocument.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A node of a parsed document.
nonisolated enum HTMLNode {
    case element(HTMLElement)
    case text(String)
}

/// One element, with its attributes and what it holds.
nonisolated final class HTMLElement {
    let name: String
    private(set) var attributes: [String: String]
    private(set) var children: [HTMLNode] = []
    weak var parent: HTMLElement?

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    func append(_ node: HTMLNode) {
        if case .element(let element) = node { element.parent = self }
        children.append(node)
    }

    /// An attribute, whichever case it was written in.
    func attribute(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    func setAttribute(_ name: String, to value: String) {
        attributes[name.lowercased()] = value
    }

    var classNames: [String] {
        (attribute("class") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var elements: [HTMLElement] {
        children.compactMap { node in
            if case .element(let element) = node { element } else { nil }
        }
    }

    /// Every element below this one, this one excluded, depth first.
    var descendants: [HTMLElement] {
        elements.flatMap { [$0] + $0.descendants }
    }

    func firstDescendant(named name: String) -> HTMLElement? {
        descendants.first { $0.name == name }
    }

    func descendants(named name: String) -> [HTMLElement] {
        descendants.filter { $0.name == name }
    }

    /// Every element below this one carrying that class name.
    func descendants(withClass className: String) -> [HTMLElement] {
        descendants.filter { $0.classNames.contains(className) }
    }

    /// The text this element holds, entities already decoded, markup dropped.
    var textContent: String {
        children.reduce(into: "") { result, node in
            switch node {
            case .text(let text): result += text
            case .element(let element):
                guard !HTMLTokenizer.rawTextElements.contains(element.name) else { return }
                result += element.textContent
            }
        }
    }
}

/// A parsed HTML document.
///
/// The tree is built the way a browser builds one, loosely : an end tag that
/// closes nothing is dropped, an element left open is closed by its parent, and
/// the elements that cannot nest close each other. It is not the HTML5 tree
/// construction algorithm, and it does not need to be : nothing here renders a
/// page, it only reads one.
nonisolated struct HTMLDocument {
    let root: HTMLElement

    /// Elements that an opening tag of the same kind closes.
    private static let closedBySelf: Set<String> = ["li", "option", "tr", "td", "th", "dt", "dd", "p"]

    /// What starting one of these closes, beyond itself.
    private static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figcaption",
        "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main", "nav",
        "ol", "p", "pre", "section", "table", "ul",
    ]

    init(_ html: String) {
        let root = HTMLElement(name: "#document")
        var stack = [root]

        for token in HTMLTokenizer.tokens(in: html) {
            switch token {
            case .text(let text):
                let decoded = HTMLEntities.decode(text)
                if !decoded.isEmpty { stack[stack.count - 1].append(.text(decoded)) }

            case .comment:
                break

            case .startTag(let name, let attributes, let isSelfClosing):
                Self.closeImplicitly(before: name, in: &stack)

                var pairs: [String: String] = [:]
                for attribute in attributes where pairs[attribute.name] == nil {
                    pairs[attribute.name] = attribute.value
                }

                let element = HTMLElement(name: name, attributes: pairs)
                stack[stack.count - 1].append(.element(element))
                if !isSelfClosing { stack.append(element) }

            case .endTag(let name):
                guard let depth = stack.lastIndex(where: { $0.name == name }), depth > 0 else { continue }
                stack.removeSubrange(depth...)
            }
        }

        self.root = root
    }

    /// Closes what the new element cannot sit inside.
    ///
    /// A `<li>` inside a `<li>` is how every hand written list is spelled, and
    /// nesting them would put half the article in the first bullet.
    private static func closeImplicitly(before name: String, in stack: inout [HTMLElement]) {
        guard stack.count > 1 else { return }
        let open = stack[stack.count - 1].name

        let closes =
            (open == name && closedBySelf.contains(name))
            || (open == "p" && closesParagraph.contains(name))
            || (open == "li" && name == "li")
            || (["dt", "dd"].contains(open) && ["dt", "dd"].contains(name))
            || (["td", "th"].contains(open) && ["td", "th", "tr"].contains(name))
            || (open == "tr" && name == "tr")

        guard closes else { return }
        stack.removeLast()
        closeImplicitly(before: name, in: &stack)
    }

    var elements: [HTMLElement] { root.descendants }

    func firstElement(named name: String) -> HTMLElement? { root.firstDescendant(named: name) }

    func elements(named name: String) -> [HTMLElement] { root.descendants(named: name) }

    func elements(withClass className: String) -> [HTMLElement] { root.descendants(withClass: className) }

    var textContent: String { root.textContent }
}
