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
/// The one colour a picture averages to.
///
/// Channels rather than a `Color` : it is worked out in Core Graphics, cached
/// off the main actor and written into a stylesheet, and none of those three
/// wants a view's colour type.
nonisolated struct Tint: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// The three channels as CSS writes them, ready to be given an alpha.
    ///
    /// Space separated and without the function around them, so that one rule
    /// in the stylesheet can decide how much of the colour to use and a
    /// generated rule has only to say which colour it is.
    var channels: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return "\(byte(red)) \(byte(green)) \(byte(blue))"
    }
}

/// The colours a picture lends the page above it.
///
/// The picture read in three bands, from its own top to its own bottom, rather
/// than the one colour it averages to : an average is a grey, since a
/// photograph averages its sky into its ground and comes out the colour of
/// neither. Read in bands, a sky stays a sky and what is under it stays under
/// it, and a page washed with them is lit the way the picture is lit.
nonisolated struct Wash: Hashable, Sendable {
    /// The top of the picture, which is usually the light in it.
    let top: Tint
    /// Its middle, which is usually what it is a picture of.
    let middle: Tint
    /// Its foot.
    let bottom: Tint
}

/// identifying user agent, a body cap, and a disk cache so a picture already
/// seen is never asked for twice.
nonisolated final class ImageStore: Sendable {
    static let shared = ImageStore()

    // **The four caches below are `nonisolated(unsafe)`.** `NSCache` locks
    // internally and is safe to read and write from any thread, which is the
    // whole reason it is used here rather than a dictionary, but it carries no
    // `Sendable` conformance to say so. The compiler has no way of knowing,
    // and this is where that is asserted.

    /// A picture past this is not a picture, it is a mistake or an attack.
    static let maximumBytes = 12 << 20

    /// A decoded picture, immutable once made, which is what lets it be shared
    /// between the task that fetched it and the screen that draws it.
    private final class Cached: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated(unsafe) private let memory = NSCache<NSString, Cached>()

    /// The average colour of each mark, by the address it came from.
    ///
    /// Keyed by address alone, where the pictures are keyed by address and
    /// size : a mark asked for at thirteen points and at seventeen is two
    /// entries there and one colour here, which is the point, since what is
    /// wanted is the colour of the publisher rather than of a thumbnail.
    nonisolated(unsafe) private let tints = NSCache<NSString, TintBox>()

    /// A colour in a cache, which takes objects and not values.
    private final class TintBox: @unchecked Sendable {
        let tint: Tint
        init(_ tint: Tint) { self.tint = tint }
    }

    /// The bands of each photograph, by the address it came from.
    ///
    /// Keyed by address alone, like the tints and for the same reason : what is
    /// wanted is the colour of the picture rather than of one thumbnail of it.
    nonisolated(unsafe) private let washes = NSCache<NSString, WashBox>()

    /// A wash in a cache, which takes objects and not values.
    private final class WashBox: @unchecked Sendable {
        let wash: Wash
        init(_ wash: Wash) { self.wash = wash }
    }

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
    nonisolated(unsafe) private let refused = NSCache<NSString, NSNumber>()
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
        tints.countLimit = 400
        washes.countLimit = 60
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
            // Worked out here, once, while the pixels are already in hand.
            //
            // **For a mark and not for a photograph.** A logo is a few dozen
            // pixels and its average is a resample of nothing ; a photograph
            // asked for at the width of a phone is a real one, it is done for
            // every picture in a list a reader scrolls through, and nothing
            // wants the average colour of a photograph.
            if maximumPixels <= Self.markPixels, let tint = Self.average(of: image) {
                tints.setObject(TintBox(tint), forKey: url.absoluteString as NSString)
            }
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

    /// Forgets every picture ever fetched, decoded or on disk.
    ///
    /// The pictures are the publishers' and only their addresses were ever
    /// stored, but the bytes themselves sit in a cache of nearly two hundred
    /// megabytes on this device, and a reader who asked for everything to go
    /// meant those too.
    func forgetEverything() {
        memory.removeAllObjects()
        tints.removeAllObjects()
        washes.removeAllObjects()
        refused.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Where a mark stops and a photograph starts, in pixels.
    static let markPixels = 128

    /// The average colour of the mark at that address, if one has been decoded.
    ///
    /// **It answers from what is held and never fetches.** The colour dresses a
    /// pill that is drawn the moment an article opens, and a pill that waited
    /// on the network to know what colour to be would be an article waiting on
    /// a favicon. The mark of the publisher whose article is being opened was
    /// almost certainly decoded a moment ago, by the row the reader pressed to
    /// open it ; where it was not, the pill wears the neutral grey and nothing
    /// is late.
    func tint(at url: URL) -> Tint? {
        guard HTTPURL.isFetchable(url) else { return nil }
        return tints.object(forKey: HTTPURL.secured(url).absoluteString as NSString)?.tint
    }

    /// How large a picture is decoded to be read for its colours.
    ///
    /// Small, since it is about to become three pixels : the bands of a
    /// photograph at sixty four pixels are the bands of the same photograph at
    /// two thousand. Wherever the picture has already been shown the bytes are
    /// the ones in the cache, so this is a decode rather than a fetch.
    static let washPixels = 64

    /// The colours the picture at that address lends the page above it.
    ///
    /// **Unlike ``tint(at:)`` this one fetches**, because it has to. The colour
    /// is wanted at the very top of the page, above the row that carries the
    /// picture and usually before that row has been built at all, so there is
    /// nothing already decoded to answer from. A pill is drawn the instant an
    /// article opens and cannot wait ; a wash is the page settling into its
    /// colour and can.
    @concurrent
    func wash(at url: URL) async throws -> Wash? {
        guard HTTPURL.isFetchable(url) else { return nil }

        let key = HTTPURL.secured(url).absoluteString as NSString
        if let held = washes.object(forKey: key) { return held.wash }

        guard
            let image = try await image(at: url, maximumPixels: Self.washPixels),
            let wash = Self.wash(of: image)
        else { return nil }

        washes.setObject(WashBox(wash), forKey: key)
        return wash
    }

    /// The one colour a picture averages to.
    ///
    /// One band of it, the band being the whole : see ``rows(of:count:)`` for
    /// the drawing, and for what is done about transparency.
    static func average(of image: CGImage) -> Tint? {
        guard let only = rows(of: image, count: 1).first else { return nil }
        return only
    }

    /// The colours a picture lends the page above it.
    ///
    /// Three bands rather than one average, for the reason ``Wash`` gives, and
    /// all three or none : a picture with a transparent band has no colour to
    /// lend there, and a wash with a hole in it is worse than no wash at all.
    static func wash(of image: CGImage) -> Wash? {
        let bands = rows(of: image, count: 3)
        guard let top = bands[0], let middle = bands[1], let bottom = bands[2] else { return nil }
        return Wash(top: top, middle: middle, bottom: bottom)
    }

    /// A picture resampled to a column of pixels, from its top to its bottom.
    ///
    /// Drawn into a bitmap one pixel wide and `count` tall, which is the whole
    /// of it : Core Graphics resamples on the way down, so each pixel is the
    /// mean of the band of the picture it stands for. The first row of the
    /// bitmap is the top of the picture, the raster beginning at the highest
    /// point of the context's own coordinates.
    ///
    /// **Transparency is divided back out.** A favicon is a logo on nothing as
    /// often as not, and a pixel that has been composited over a transparent
    /// ground comes back premultiplied : a red logo covering a fifth of its
    /// square averages to a fifth of red, which is a very pale pink rather than
    /// red. Dividing by the alpha gives the colour of what was actually drawn,
    /// which is the logo. A band with nothing in it at all has no colour, and
    /// says so.
    private static func rows(of image: CGImage, count: Int) -> [Tint?] {
        var pixels = [UInt8](repeating: 0, count: count * 4)
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: 1,
                    height: count,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmap
                )
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: count))
            return true
        }
        guard drawn else { return Array(repeating: nil, count: count) }

        return (0..<count).map { band in
            let start = band * 4
            let alpha = Double(pixels[start + 3]) / 255
            guard alpha > 0.05 else { return nil }

            return Tint(
                red: min(Double(pixels[start]) / 255 / alpha, 1),
                green: min(Double(pixels[start + 1]) / 255 / alpha, 1),
                blue: min(Double(pixels[start + 2]) / 255 / alpha, 1)
            )
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
/// Who a picture came with, set inside it.
///
/// **A picture on the page belongs to somebody, and the page says who.** Only
/// the address is ever stored : the file stays the publisher's and is asked for
/// from their own server when a screen shows it, so the least a screen owes
/// them is a line saying whose it is. A story is several rooms and the picture
/// is one room's, which the marks beside the headline do not answer.
///
/// **The name and nothing else.** A caption was set under the picture first,
/// reading `Image via Le Monde`, and it cost a line of the page under every
/// picture on it to say a thing a name already says : a name in the corner of a
/// photograph is a credit by the oldest convention there is, and nobody has to
/// be told what it is doing there. The words survive as the accessibility
/// label, where there is no corner to put a name in.
///
/// **And never a byline.** What Flong knows is the article the picture arrived
/// with, and nothing else : the publisher may have credited an agency, a
/// photographer or nobody at all, and none of that reaches a feed. This says
/// where the picture came from and makes no claim about who made it.
///
/// **On glass, which is the one place in the content it is allowed.** Text laid
/// straight over a photograph is unreadable on half the photographs there are,
/// and the usual answer is a scrim, which is a dark band across a picture the
/// reader came to look at. The pill is the size of the name, it takes what is
/// under it and keeps the picture whole around it. It is a handful per screen
/// rather than one per row, which is what the hairline edge of a picture
/// refused glass for.
struct PictureCredit: View {
    /// How large the pill is drawn.
    ///
    /// **Two sizes, and not one scaled down.** A credit is set against the
    /// picture it belongs to, not against the page : the same pill that reads
    /// as a caption in the corner of a lead running the whole measure is a
    /// label stuck across the corner of a ninety-six point thumbnail. What has
    /// to stay constant is the share of the picture it takes, which means the
    /// pill and the type inside it both come down together.
    enum Size {
        /// A picture running the whole measure : the lead, and a story page.
        case full
        /// A picture beside a story or an article, ninety-six points wide.
        case compact

        /// A text style where there is room for one, and a fixed size where
        /// there is not.
        ///
        /// The lead runs the whole measure, so its credit grows with the
        /// reader's type size like everything else on the page. A thumbnail is
        /// ninety-six points wide whatever the type size, so a pill that grew
        /// inside it would end up being the picture : what a reader who cannot
        /// read nine points needs there is the name read out, and the
        /// accessibility label is where it is.
        var font: Font {
            switch self {
            case .full: .caption2
            case .compact: .system(size: 9)
            }
        }

        /// How much of the pill is air around the name.
        var padding: (horizontal: CGFloat, vertical: CGFloat) {
            switch self {
            case .full: (7, 3)
            case .compact: (5, 2)
            }
        }

        /// How far the pill sits in from the corner of the picture.
        var inset: CGFloat {
            switch self {
            case .full: 5
            case .compact: 4
            }
        }
    }

    /// The publisher whose article the picture came with.
    let domain: String?
    var size = Size.full

    @Environment(\.publishers) private var publishers

    @ViewBuilder
    var body: some View {
        if let domain {
            let name = publishers[domain]?.name ?? domain

            // Verbatim : a publisher's name is either an address or something
            // the reader wrote, and neither is translated.
            //
            // **One line, shrunk to fit, and never cut.** A credit ending in
            // `theguard…` credits nobody. Wrapping was tried : two lines of it
            // fill most of a thumbnail and break the name across a hyphen, so
            // the pill ends up being the picture. Shrinking is what is left,
            // and at the compact size it is reached only by a name longer than
            // any address, which a thumbnail cannot hold legibly by any means.
            Text(verbatim: name)
                .font(size.font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, size.padding.horizontal)
                .padding(.vertical, size.padding.vertical)
                .glassEffect(.regular, in: .capsule)
                .padding(size.inset)
                .accessibilityLabel(Text("Picture via \(name)"))
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    /// The publisher whose article the picture came with, credited in the
    /// corner of it. Drawn only where there is a picture to credit.
    var credit: String?
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
                // The picture is decorative and hidden from VoiceOver ; the
                // credit over it is not, being the only place the attribution
                // is written at all.
                framed(Image(decorative: image, scale: displayScale).resizable().scaledToFill())
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottomTrailing) {
                        PictureCredit(domain: credit, size: creditSize)
                    }
            } else if isLoading, url != nil {
                framed(Rectangle().fill(.quaternary))
                    .accessibilityHidden(true)
            }
        }
        .task(id: url) { await load() }
    }

    /// How large the credit is drawn : the picture's own size decides it, so a
    /// call site cannot ask for a lead's caption on a thumbnail.
    private var creditSize: PictureCredit.Size {
        (width ?? side) == nil ? .full : .compact
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
