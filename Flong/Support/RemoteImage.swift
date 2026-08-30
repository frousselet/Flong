//
//  RemoteImage.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import os

/// Fetches the pictures articles carry, and keeps them.
///
/// Not `AsyncImage`, for two reasons that both show on a list of five hundred
/// rows. It keeps no decoded image, so scrolling back up decodes everything
/// again ; and it decodes at full size, so a two thousand pixel wide photograph
/// is unpacked whole to fill a sixty four point square. `ImageIO` makes the
/// thumbnail directly from the encoded bytes, which is both faster and an order
/// of magnitude cheaper in memory.
///
/// The politeness of `docs/technical/fetching.md` applies here too : the same
/// identifying user agent, a body cap, and a disk cache so a picture already
/// seen is never asked for twice.
nonisolated final class ImageStore: Sendable {
    static let shared = ImageStore()

    /// A picture past this is not a picture, it is a mistake or an attack.
    static let maximumBytes = 12 << 20

    /// A decoded picture, immutable once made, which is what lets it be shared
    /// between the task that fetched it and the screen that draws it.
    private final class Cached: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let memory = NSCache<NSString, Cached>()

    /// Addresses that answered with something that is not a picture.
    ///
    /// Without this the same failure is repeated for ever : a row scrolling
    /// back into view runs its task again, so one broken favicon in a list is
    /// one fetch and one decode per appearance, and one line in the console
    /// each time. A cache rather than a set, so it empties itself.
    private let refused = NSCache<NSString, NSNumber>()
    private let session: URLSession
    private static let log = Logger(subsystem: "com.rslt.Flong", category: "images")

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 192 << 20, directory: nil)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpAdditionalHeaders = [
            "User-Agent": FeedFetcher.defaultUserAgent,
            "Accept": "image/*;q=0.9,*/*;q=0.1",
        ]
        session = URLSession(configuration: configuration)

        // Decoded thumbnails, not originals : a few hundred of them are a few
        // megabytes, and the system empties this under pressure anyway.
        memory.countLimit = 400
        refused.countLimit = 500
    }

    /// The picture at that address, decoded no larger than it will be drawn.
    func image(at url: URL, maximumPixels: Int) async throws -> CGImage? {
        // The last guard before the network. Everything upstream resolves and
        // vets its addresses ; this is what makes a hole upstream a picture
        // that does not appear rather than an error in the reader's console.
        guard HTTPURL.isFetchable(url) else { return nil }

        // A feed states `http` for a picture the site has been serving over
        // TLS for years, and App Transport Security refuses the request before
        // the redirect that would have fixed it.
        let url = HTTPURL.secured(url)

        let key = "\(url.absoluteString)|\(maximumPixels)" as NSString
        if let cached = memory.object(forKey: key) { return cached.image }
        if refused.object(forKey: url.absoluteString as NSString) != nil { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard data.count <= Self.maximumBytes else {
            Self.log.notice("Picture too large, ignored : \(data.count, privacy: .public) bytes")
            return nil
        }
        guard let image = Self.thumbnail(from: data, maximumPixels: maximumPixels) else {
            refused.setObject(1, forKey: url.absoluteString as NSString)
            return nil
        }

        memory.setObject(Cached(image), forKey: key)
        return image
    }

    /// Whether there is a picture in there at all.
    ///
    /// A source is made from any bytes at all and says nothing about it :
    /// asking such a one for a thumbnail is what puts
    /// `failed to create thumbnail [-50]` in the reader's console, once per
    /// attempt, with the type printed as `n/a` because there is not one. A
    /// server answering a redirect page, or an address that was never a
    /// picture, lands here.
    ///
    /// The status matters as much as the type : a download cut short leaves a
    /// source of the right type and not enough of it, which fails the same way
    /// and just as loudly.
    private static func holdsAPicture(_ source: CGImageSource) -> Bool {
        CGImageSourceGetType(source) != nil
            && CGImageSourceGetCount(source) > 0
            && CGImageSourceGetStatus(source) == .statusComplete
    }

    /// The encoded bytes, decoded once, at the size they are needed.
    private static func thumbnail(from data: Data, maximumPixels: Int) -> CGImage? {
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        guard let source, Self.holdsAPicture(source) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // A photograph carries its orientation in its metadata, and a
            // thumbnail that ignores it comes out on its side.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A picture from the network, drawn at the size it is shown.
///
/// A fixed square, a fixed width at a stated ratio, or the width it is offered
/// at that ratio : a source's mark, a thumbnail beside a headline, and the
/// photograph above a lead story.
///
/// It occupies nothing until it has something to show, and nothing again if the
/// address turns out to be dead : a grey rectangle where a photograph failed is
/// worse than no photograph, and a page of them looks broken. The picture is
/// decorative and hidden from VoiceOver : feeds almost never carry alternative
/// text, and reading a headline out twice helps nobody.
struct RemoteImage: View {
    let url: URL?
    /// A fixed side, for a picture that must be square whatever it holds :
    /// a source's own mark, which is square by every convention there is.
    var side: CGFloat?
    /// A fixed width, the height following from `aspect`.
    var width: CGFloat?
    var aspect: CGFloat = Editorial.pictureAspect
    var corner: CGFloat = 8

    /// How wide the ring of glass around a picture is drawn.
    ///
    /// A hairline. A publisher's picture arrives at whatever contrast it was
    /// shot at, and one that ends in white sits on a white page with no edge at
    /// all : the ring is what says where the picture stops. Glass rather than a
    /// grey rule, since it takes its light from the picture it holds and from
    /// the page around it, and so reads on a photograph of a night sky as well
    /// as on one of a beach.
    static let ring: CGFloat = 1.5

    @State private var image: CGImage?
    @State private var isLoading = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                framed(Image(decorative: image, scale: displayScale).resizable().scaledToFill())
            } else if isLoading, url != nil {
                framed(Rectangle().fill(.quaternary))
            }
        }
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func framed(_ content: some View) -> some View {
        if let side {
            ringed(content.frame(width: side, height: side))
        } else if let width {
            ringed(content.frame(width: width, height: (width / aspect).rounded()))
        } else {
            ringed(
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay { content }
            )
        }
    }

    /// The picture, cut to its corner and set in a ring of glass.
    ///
    /// The glass is behind rather than over : a material lends its vibrancy to
    /// whatever it holds, which would wash a photograph the way it washed the
    /// bars of the arrivals chart. Behind, it is a frame the picture sits in.
    ///
    /// The outer corner is the inner one plus the ring, so the two curves are
    /// concentric. Equal radii would leave the frame looking thicker at the
    /// corners than along the sides.
    private func ringed(_ content: some View) -> some View {
        content
            .clipShape(.rect(cornerRadius: corner))
            .padding(Self.ring)
            .background {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: corner + Self.ring))
            }
    }

    private func load() async {
        image = nil
        isLoading = url != nil
        guard let url else { return }

        let points = side ?? width ?? Editorial.measure
        let loaded = try? await ImageStore.shared.image(
            at: url,
            maximumPixels: max(Int(points * displayScale), 1)
        )

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            image = loaded
            isLoading = false
        }
    }
}
