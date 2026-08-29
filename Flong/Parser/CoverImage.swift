//
//  CoverImage.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The picture that stands for an article.
///
/// Publishers state it in five different places and agree on none of them, so
/// the answer is a documented order rather than a guess :
///
/// 1. **What the feed says the article's picture is** : `media:thumbnail`,
///    `media:content` of an image, `itunes:image`, JSON Feed's `image` or
///    `banner_image`, an `u-photo`. A statement about the article beats
///    anything inferred from its body.
/// 2. **An attached image**, when a feed encloses one rather than naming it.
/// 3. **The first picture in the body**, which is what a reader would call the
///    article's picture if asked.
///
/// The body is read after sanitizing, never before : the sanitizer has already
/// resolved every address against the article, vetted its scheme and thrown out
/// the tracking pixels, so what is left is both absolute and safe to ask for.
nonisolated enum CoverImage {
    /// Below this, on its longest stated side, a picture is furniture : a
    /// spacer, a share button, a badge, a rating star.
    static let minimumSide = 64

    private static let extensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "avif"]

    static func of(_ item: ParsedItem, sanitizedHTML: String? = nil) -> URL? {
        if let stated = item.imageURL { return stated }
        if let attached = item.enclosures.first(where: isImage)?.url { return attached }
        guard let sanitizedHTML else { return nil }
        return inBody(sanitizedHTML)
    }

    /// Whether an enclosure is a picture rather than a sound or a film.
    ///
    /// The type is authoritative when the feed states one. Half of them do not,
    /// and the address is then all there is to go on.
    static func isImage(_ enclosure: Enclosure) -> Bool {
        if let type = enclosure.type?.lowercased(), !type.isEmpty {
            return type.hasPrefix("image/")
        }
        return extensions.contains(enclosure.url.pathExtension.lowercased())
    }

    /// The first picture in a sanitized body worth putting on a page.
    static func inBody(_ html: String) -> URL? {
        for image in HTMLDocument(html).elements(named: "img") {
            guard !isFurniture(image) else { continue }
            guard let source = image.attribute("src"), let url = URL(string: source) else { continue }
            guard url.scheme?.lowercased().hasPrefix("http") == true else { continue }
            return url
        }
        return nil
    }

    /// A picture the publisher itself declares small is not the article's.
    ///
    /// Only stated dimensions are read. Asking the network how big a picture is
    /// before deciding whether to show it would mean fetching every image of
    /// every article, which is exactly the traffic a feed reader owes it to
    /// publishers not to generate.
    private static func isFurniture(_ element: HTMLElement) -> Bool {
        for name in ["width", "height"] {
            guard let value = element.attribute(name), let size = Int(value.filter(\.isNumber)) else { continue }
            if size < minimumSide { return true }
        }
        return false
    }
}
