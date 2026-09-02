//
//  NotificationPicture.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
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
import UserNotifications

/// The photograph a notice is shown beside.
///
/// **A headline with its picture is the article ; a headline alone is a line of
/// text.** The notification centre draws the attachment as a thumbnail beside
/// the two lines and full width when the notice is pulled open, which is the
/// whole of what this exists for : the reader recognizes the piece before they
/// have read the headline.
///
/// **The system takes a file and nothing else**, so the address has to become
/// bytes on disk before a notification can carry it, which is why this is here
/// and not in ``Announcement`` : that one is a sentence written from names, and
/// stays testable without a network.
///
/// **One request per notice posted, and usually none.** It goes through
/// ``ImageStore``, so a picture the article list has already shown costs
/// nothing at all, and the one fetched here is in hand when the reader taps
/// through to the article. The politeness of `docs/technical/fetching.md`
/// applies : the same identifying user agent, the same body cap, the same
/// cache.
nonisolated enum NotificationPicture {
    /// How large the picture is decoded, on its longest side.
    ///
    /// Wide enough for the expanded notice on the largest phone there is, and
    /// no wider : what is drawn is a banner, not a page, and a photograph
    /// decoded at its published size would be several megabytes handed to the
    /// system to shrink again.
    static let pixels = 1024

    /// The picture at that address, fetched, decoded and written where the
    /// system can take it from, with the file it was written to.
    ///
    /// **The file comes back because somebody has to put it away.** The system
    /// takes its own copy and leaves this one exactly where it was found, so a
    /// notice posted every hour is a photograph left in `tmp` every hour. The
    /// caller holds it until the request is added and then throws it out : see
    /// ``Notifier/post(_:)``.
    ///
    /// `nil` for everything that can go wrong, and none of it is worth telling
    /// the reader about : a notice with its photograph missing is the notice,
    /// and a notice held back because a publisher's server was slow is nothing
    /// at all.
    @concurrent
    static func attachment(for url: URL) async -> (attachment: UNNotificationAttachment, file: URL)? {
        guard let image = try? await ImageStore.shared.image(at: url, maximumPixels: pixels) else { return nil }
        guard let written = write(image) else { return nil }

        do {
            // The type stated rather than guessed at from the path : the file
            // is named after nothing in particular, and a hint is cheaper than
            // having the system sniff bytes it has just been handed.
            let attachment = try UNNotificationAttachment(
                identifier: UUID().uuidString,
                url: written.file,
                options: [UNNotificationAttachmentOptionsTypeHintKey: written.type.identifier]
            )
            return (attachment, written.file)
        } catch {
            try? FileManager.default.removeItem(at: written.file)
            Log.notify.error("A notification picture was refused : \(error, privacy: .public)")
            return nil
        }
    }

    /// The decoded picture written to a file of its own.
    ///
    /// **Re-encoded rather than passed through.** Publishers serve WebP and
    /// AVIF now, and a notification attachment is limited to the handful of
    /// types the system will draw ; the bytes are already decoded by the time
    /// they get here, so writing them back out in a type that is certainly
    /// accepted costs one encode and removes the whole question.
    ///
    /// **JPEG for a photograph and PNG for anything with transparency.** Nearly
    /// every cover is a photograph, and a photograph written as PNG is several
    /// times the file for no gain ; a logo on nothing written as JPEG comes out
    /// on a black square.
    static func write(_ image: CGImage) -> (file: URL, type: UTType)? {
        let type: UTType = hasTransparency(image) ? .png : .jpeg
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "jpg")

        guard
            let destination = CGImageDestinationCreateWithURL(
                file as CFURL,
                type.identifier as CFString,
                1,
                nil
            )
        else { return nil }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return (file, type)
    }

    /// Whether the picture has anything to lose by being flattened.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}
