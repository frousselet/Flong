//
//  ProfilePicture.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// The reader's own face, cut down to something a preference can carry.
///
/// **Scaled before it is stored, never after.** What comes out of a photo
/// library is a photograph : twelve megapixels, four megabytes, and a colour
/// profile. What is wanted is a mark twenty-six points across in a toolbar. The
/// picture is resized once, on the way in, and what is kept is the small
/// version : storing the original and shrinking it at each draw would put a
/// photograph in a store that holds one megabyte for everything.
///
/// It is re-encoded as JPEG rather than kept in whatever it arrived as, so that
/// a HEIC from a phone and a PNG from a Mac take the same room and decode the
/// same way on both.
nonisolated enum ProfilePicture {
    /// The largest side the stored picture may have, in pixels.
    ///
    /// Twice over what the largest place it is shown needs at three times
    /// scale, so it stays crisp if it is ever shown larger, and small enough
    /// that a photograph of any size lands in a few tens of kilobytes.
    static let side = 256

    static let quality = 0.85

    /// Scales and re-encodes what the reader chose.
    ///
    /// Returns `nil` for anything that is not an image, which includes the file
    /// somebody picked by mistake.
    static func scaled(_ data: Data) -> Data? {
        // A source is made from any bytes at all and says nothing about it.
        // Asking such a one for a thumbnail is what puts `failed to create
        // thumbnail [-50]` in the console, with the type printed as `n/a`
        // because there is not one : a file picked by mistake is refused here,
        // quietly, rather than one line further down and loudly.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) != nil,
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatus(source) == .statusComplete
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Photographs carry their rotation in metadata, and a thumbnail
            // that ignores it comes out on its side.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let encoded = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                encoded,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else { return nil }

        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }

        let result = encoded as Data
        guard result.count <= Preferences.pictureLimit else {
            Log.store.error("A picture scaled to \\(side) still came to \\(result.count) bytes.")
            return nil
        }
        return result
    }

    /// The picture, ready to draw.
    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// What stands in for a face when there is none : the reader's initials.
    ///
    /// Two letters at most, taken from the first character of each name rather
    /// than from the first two of the first, so `François Rousselet` gives `FR`
    /// and not `FR` by accident. A name in a script with no case, or one made
    /// of a single word, gives what it gives : nothing is invented.
    static func initials(first: String, last: String) -> String? {
        let letters = [first, last]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { $0.first }
            .map { String($0).localizedUppercase }

        return letters.isEmpty ? nil : letters.joined()
    }
}
