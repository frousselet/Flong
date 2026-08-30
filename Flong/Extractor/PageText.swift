//
//  PageText.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Reads a page's bytes as text.
///
/// A web page states its encoding twice, in the `Content-Type` header and in a
/// `<meta>` near the top, and either may be wrong or missing. French pages in
/// particular are still served as Latin-1 by servers old enough to have been
/// configured in the nineties, and reading those as UTF-8 turns every accent
/// into a question mark.
///
/// The header first, since it is what the server means today ; the `<meta>`
/// next, since it is what the page was written as ; UTF-8 after that, since it
/// is what everything is now ; and Latin-1 last, which decodes any bytes at all
/// and so can never fail. Nothing here gives up : a page read slightly wrong is
/// better than no page.
nonisolated enum PageText {
    static func text(of data: Data, contentType: String?) -> String {
        if let named = charset(inContentType: contentType), let text = String(data: data, encoding: named) {
            return text
        }

        // The declaration lives in the first few hundred bytes, which are ASCII
        // whatever the rest turns out to be.
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        if let declared = charset(inMeta: head), let text = String(data: data, encoding: declared) {
            return text
        }

        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }

    /// The charset a `Content-Type` names, when it names one.
    static func charset(inContentType contentType: String?) -> String.Encoding? {
        guard let contentType else { return nil }

        for part in contentType.components(separatedBy: ";") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard piece.lowercased().hasPrefix("charset=") else { continue }

            let name = piece.dropFirst("charset=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\" '"))
            return encoding(named: name)
        }
        return nil
    }

    /// The charset a page's own `<meta>` names.
    ///
    /// Both spellings : the short `<meta charset>` of HTML5 and the long
    /// `http-equiv` form, which the pages that need this most are written in.
    static func charset(inMeta head: String) -> String.Encoding? {
        let lower = head.lowercased()

        for marker in ["charset=\"", "charset='", "charset="] {
            var searched = lower[...]
            while let range = searched.range(of: marker) {
                let rest = lower[range.upperBound...]
                let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                if let encoding = encoding(named: String(name)) { return encoding }
                searched = rest
            }
        }
        return nil
    }

    /// The encodings worth honouring, by the names pages use for them.
    ///
    /// A short list on purpose, and every entry is the encoding it says it is.
    /// `iso-8859-15` is not here : Foundation has no Latin-9, and mapping it to
    /// a neighbour would decode French as Central European, which is worse than
    /// falling through to the UTF-8 and Latin-1 attempts below.
    static func encoding(named name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8": .utf8
        case "iso-8859-1", "iso8859-1", "latin1", "latin-1": .isoLatin1
        case "windows-1252", "cp1252": .windowsCP1252
        case "us-ascii", "ascii": .ascii
        default: nil
        }
    }
}
