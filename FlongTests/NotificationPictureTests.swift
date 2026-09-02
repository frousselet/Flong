//
//  NotificationPictureTests.swift
//  FlongTests
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
import Testing
import UniformTypeIdentifiers
import UserNotifications

@testable import Flong

/// The picture a notification is shown beside.
///
/// The delivery itself needs an authorization, a bundle and a device, and is
/// not exercised here any more than the rest of the notifications are. What is
/// testable is the step between an address and something the system will take :
/// which type the bytes are written as, that the file is a picture when it is
/// read back, and that an address nobody should be asking a server for never
/// becomes a request.
@Suite("The picture a notice is shown beside")
struct NotificationPictureTests {
    /// A picture of a stated size, opaque or not.
    private func picture(_ side: Int, transparent: Bool) throws -> CGImage {
        let alpha =
            transparent
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: alpha | CGBitmapInfo.byteOrder32Big.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
        return try #require(context.makeImage())
    }

    /// Whatever the file was, so a passing test leaves nothing behind.
    private func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    @Test("A photograph is written as JPEG, and reads back as one")
    func photograph() throws {
        let written = try #require(NotificationPicture.write(picture(64, transparent: false)))
        defer { remove(written.file) }

        // A photograph written as PNG is several times the file for no gain.
        #expect(written.type == .jpeg)
        #expect(written.file.pathExtension == "jpeg")

        let source = try #require(CGImageSourceCreateWithURL(written.file as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)).width == 64)
    }

    @Test("A picture with transparency is written as PNG, which keeps it")
    func transparency() throws {
        let written = try #require(NotificationPicture.write(picture(64, transparent: true)))
        defer { remove(written.file) }

        // A logo on nothing written as JPEG comes out on a black square.
        #expect(written.type == .png)
        #expect(written.file.pathExtension == "png")

        let source = try #require(CGImageSourceCreateWithURL(written.file as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    @Test("What has nothing to lose by being flattened is flattened")
    func flattening() throws {
        #expect(!NotificationPicture.hasTransparency(try picture(8, transparent: false)))
        #expect(NotificationPicture.hasTransparency(try picture(8, transparent: true)))
    }

    @Test("Two pictures never land on the same file")
    func distinctFiles() throws {
        let image = try picture(8, transparent: false)
        let first = try #require(NotificationPicture.write(image))
        let second = try #require(NotificationPicture.write(image))
        defer {
            remove(first.file)
            remove(second.file)
        }

        // Notices overlap : a background pass may post two within a moment of
        // each other, and the system moves the file out from under whoever
        // wrote it second.
        #expect(first.file != second.file)
    }

    /// The one thing here the system has an opinion about. Everything else is
    /// this application's own code ; whether a file it has just written is a
    /// file the notification centre will accept is the system's answer, and it
    /// is the answer the whole feature rests on. Both types, since the choice
    /// between them is made on the picture and not on what is known to work.
    @Test("The system takes what is written for it, and says which type it is")
    func accepted() throws {
        for transparent in [false, true] {
            let written = try #require(NotificationPicture.write(picture(64, transparent: transparent)))
            defer { remove(written.file) }

            let attachment = try UNNotificationAttachment(
                identifier: UUID().uuidString,
                url: written.file,
                options: [UNNotificationAttachmentOptionsTypeHintKey: written.type.identifier]
            )
            #expect(attachment.type == written.type.identifier)
        }
    }

    @Test("An address that is not the web is never asked for")
    func notTheWeb() async {
        // The last guard before the network, which is ``ImageStore``'s own :
        // a `file:` or `data:` address in a feed is not a picture to fetch, and
        // nothing here should turn one into a request.
        #expect(await NotificationPicture.attachment(for: URL(string: "file:///etc/passwd")!) == nil)
        #expect(await NotificationPicture.attachment(for: URL(string: "data:image/png;base64,AA")!) == nil)
    }
}
