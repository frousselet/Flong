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
    ///
    /// **Only what will never be a picture goes in here.** It used to take
    /// anything that failed to decode, and a download cut short fails to decode
    /// : a picture whose bytes were truncated once, which is what happens when
    /// sixty feeds and their photographs are fetched at the same moment, was
    /// refused for the rest of the process. Nothing cleared it but quitting the
    /// application, which is exactly how it was reported : the lead story's
    /// photograph missing until a relaunch.
    private let refused = NSCache<NSString, NSNumber>()
    private let session: URLSession
    private static let log = Logger(subsystem: "com.rslt.Flong", category: "images")

    init() {
        let configuration = URLSessionConfiguration.default
        // A list scrolled quickly asks for every picture it passes. The
        // requests are cancelled as their rows leave, but a burst of hundreds
        // opening at once is a burst the network stack complains about and the
        // device pays for : four at a time is enough to keep a screen filled.
        configuration.httpMaximumConnectionsPerHost = 4
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
    ///
    /// **`@concurrent`, and the whole freeze is in that word.** The target
    /// builds with `SWIFT_APPROACHABLE_CONCURRENCY`, under which a
    /// `nonisolated async` function runs on its caller's actor rather than on
    /// the pool. Every caller of this is a view, so every caller is the main
    /// actor, so the ImageIO decode below was happening on the main thread :
    /// one picture at a time, a few milliseconds each, for every row a reader
    /// scrolls past. That is a list that stops moving while it fills.
    ///
    /// It never showed on a simulator, where a Mac decodes a photograph faster
    /// than a frame lasts. It shows on a phone.
    @concurrent
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
        switch Self.decode(data, maximumPixels: maximumPixels) {
        case .picture(let image):
            memory.setObject(Cached(image), forKey: key)
            return image

        case .notAPicture:
            refused.setObject(1, forKey: url.absoluteString as NSString)
            return nil

        case .cutShort:
            // Worth asking for again : what arrived was the beginning of a
            // picture, and the next attempt may get the rest of it.
            return nil
        }
    }

    /// What a set of bytes turned out to be.
    private enum Decoded {
        case picture(CGImage)
        /// Bytes that are not a picture and will not become one however often
        /// they are asked for : a redirect page, an address that was never a
        /// picture, a file whose data is broken.
        case notAPicture
        /// The beginning of a picture. A download cut short leaves a source of
        /// the right type and not enough of it.
        case cutShort
    }

    /// Whether a source that will not decode is one worth asking for again.
    ///
    /// **The status is what tells the two apart, and conflating them is what
    /// lost the pictures.** A source is made from any bytes at all and says
    /// nothing about it : asking such a one for a thumbnail is what puts
    /// `failed to create thumbnail [-50]` in the reader's console, with the
    /// type printed as `n/a` because there is not one. A redirect page or an
    /// address that was never a picture lands there and is never worth asking
    /// for again.
    ///
    /// A download cut short fails in exactly the same place and is the opposite
    /// case : the bytes are the beginning of a real picture, and the next
    /// attempt may well get the rest. Refusing those was how one busy moment,
    /// sixty feeds and their photographs arriving at once, cost a story its
    /// photograph for the whole life of the process.
    private static func isWorthAskingAgain(_ status: CGImageSourceStatus) -> Bool {
        switch status {
        case .statusIncomplete, .statusReadingHeader, .statusUnexpectedEOF: true
        default: false
        }
    }

    /// The encoded bytes, decoded once, at the size they are needed.
    private static func decode(_ data: Data, maximumPixels: Int) -> Decoded {
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        guard let source, CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 else {
            return .notAPicture
        }

        let status = CGImageSourceGetStatus(source)
        guard status == .statusComplete else {
            return isWorthAskingAgain(status) ? .cutShort : .notAPicture
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // A photograph carries its orientation in its metadata, and a
            // thumbnail that ignores it comes out on its side.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Complete, typed, and still unusable : the file is broken rather
            // than half here, and asking again would break the same way.
            return .notAPicture
        }
        return .picture(image)
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
    /// A hairline, drawn inside the picture's own edge.
    ///
    /// **Inside and not around.** A ring outside is a mount, and a mount is a
    /// frame doing more than saying where the picture ends. Inside, the line is
    /// part of the picture's own edge and takes no room at all : nothing moves
    /// to make space for it.
    ///
    /// **A line and not a material.** Glass was tried at a point and a half and
    /// read as a band ; taken down to a hairline the regular material is a pale
    /// smear and the clear one is nothing whatever, measured at pure white
    /// against a white page. What is wanted here is an edge, and an edge is a
    /// line. It is also hundreds fewer glass effects in a list somebody is
    /// scrolling.
    /// Half a point, and half of the separator's colour with it.
    ///
    /// A point was tried and read as too much : on a two times screen half a
    /// point is a single device pixel, which is exactly what an edge is. It
    /// says where the picture stops and is never the thing one looks at.
    static let ring: CGFloat = 0.5

    /// How much of the separator the edge keeps.
    ///
    /// The separator's own colour is drawn to be read as a rule between two
    /// things, and this is not that : it is the last pixel of the picture
    /// rather than something between the picture and the page. Half of it says
    /// where the edge is without ever being the thing one looks at.
    static let ringOpacity: Double = 0.5

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

    /// The picture, cut to its corner and edged with a hairline inside it.
    ///
    /// `strokeBorder` and not `stroke` : a stroke straddles the path and half
    /// of it would fall outside the clip, which is a line drawn at half its
    /// width and softer on one side than the other.
    ///
    /// The separator's own colour rather than a white highlight. White is the
    /// glass idiom and it disappears on the picture that most needs an edge,
    /// which is the one ending in white on a white page ; the separator is a
    /// hairline that holds against both, and turns with the appearance.
    private func ringed(_ content: some View) -> some View {
        content
            .clipShape(.rect(cornerRadius: corner))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.separator.opacity(Self.ringOpacity), lineWidth: Self.ring)
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
