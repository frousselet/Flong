//
//  OPMLReader.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Why an OPML file could not be read.
nonisolated enum OPMLError: Error, Hashable, Sendable {
    /// The bytes are not XML, even after the repair pass.
    case unreadable
    /// Well formed, but it holds no `opml` element.
    case notOPML
}

/// Reads an OPML file into an ``OPMLDocument``.
///
/// Exported OPML is routinely broken : a bare ampersand in a title, a control
/// character in the middle of a description, an encoding the declaration lies
/// about. Section 19 of the specification asks for tolerance, so a file that
/// `XMLParser` refuses is repaired once and parsed again, rather than being
/// handed back to the reader as a failure.
nonisolated enum OPMLReader {
    static func read(_ data: Data) throws -> OPMLDocument {
        do {
            return try parse(data)
        } catch OPMLError.unreadable {
            return try parse(XMLRepair.repaired(data))
        }
    }

    private static func parse(_ data: Data) throws -> OPMLDocument {
        let parser = XMLParser(data: data)
        let delegate = Builder()
        parser.delegate = delegate

        guard parser.parse() else { throw OPMLError.unreadable }
        guard delegate.sawOPML else { throw OPMLError.notOPML }
        return delegate.document
    }

    // MARK: - Parsing

    /// Builds the tree as `XMLParser` walks the file.
    private final class Builder: NSObject, XMLParserDelegate {
        private(set) var document = OPMLDocument()
        private(set) var sawOPML = false

        private var stack: [OPMLOutline] = []
        private var headTitle: String?
        private var isInHeadTitle = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            switch elementName.lowercased() {
            case "opml":
                sawOPML = true
            case "title":
                isInHeadTitle = true
            case "outline":
                stack.append(
                    OPMLOutline(
                        text: Builder.attribute("text", of: attributes),
                        title: Builder.attribute("title", of: attributes),
                        xmlURL: Builder.attribute("xmlUrl", of: attributes),
                        htmlURL: Builder.attribute("htmlUrl", of: attributes),
                        type: Builder.attribute("type", of: attributes),
                        category: Builder.attribute("category", of: attributes)
                    )
                )
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            switch elementName.lowercased() {
            case "title":
                isInHeadTitle = false
                if document.title == nil, let headTitle, !headTitle.isEmpty {
                    document.title = headTitle
                }
                headTitle = nil
            case "outline":
                guard let outline = stack.popLast() else { return }
                if stack.isEmpty {
                    document.outlines.append(outline)
                } else {
                    stack[stack.count - 1].children.append(outline)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard isInHeadTitle else { return }
            headTitle = (headTitle ?? "") + string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Reads an attribute whatever case the exporter wrote it in.
        ///
        /// `xmlUrl`, `xmlurl` and `XMLURL` all appear in files that are otherwise
        /// perfectly valid.
        private static func attribute(_ name: String, of attributes: [String: String]) -> String? {
            let value =
                attributes[name] ?? attributes.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }
}
