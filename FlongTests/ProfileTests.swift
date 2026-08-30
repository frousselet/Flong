//
//  ProfileTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import GRDB
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Flong

@Suite("Who is reading")
struct ProfileTests {
    /// A photograph, as far as this suite is concerned : big enough that the
    /// scaling has something to do.
    func photograph(side: Int = 1600) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        // Something with detail in it : a flat fill compresses to nothing and
        // would make a size test say whatever we wanted.
        for x in stride(from: 0, to: side, by: 8) {
            for y in stride(from: 0, to: side, by: 8) {
                context.setFillColor(
                    red: Double((x * y) % 255) / 255,
                    green: Double(x % 255) / 255,
                    blue: Double(y % 255) / 255,
                    alpha: 1
                )
                context.fill(CGRect(x: x, y: y, width: 8, height: 8))
            }
        }

        let image = try #require(context.makeImage())
        let out = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    // MARK: - The picture

    @Test("A photograph is cut down to something a preference can carry")
    func scaling() throws {
        let original = try photograph()
        let scaled = try #require(ProfilePicture.scaled(original))

        // Well under the store's share, which is the whole point of scaling on
        // the way in rather than at each draw.
        #expect(scaled.count <= Preferences.pictureLimit)
        #expect(scaled.count < original.count)

        let image = try #require(ProfilePicture.image(scaled))
        #expect(max(image.width, image.height) == ProfilePicture.side)
    }

    @Test("A picture already small enough is still made square-ish and kept")
    func smallPicture() throws {
        let scaled = try #require(ProfilePicture.scaled(try photograph(side: 64)))
        let image = try #require(ProfilePicture.image(scaled))

        // Nothing is enlarged : a small picture stays its own size.
        #expect(max(image.width, image.height) == 64)
    }

    @Test("Anything that is not an image is refused")
    func notAnImage() {
        #expect(ProfilePicture.scaled(Data("this is not a photograph".utf8)) == nil)
        #expect(ProfilePicture.scaled(Data()) == nil)
        #expect(ProfilePicture.image(Data("nor is this".utf8)) == nil)
    }

    // MARK: - The initials

    @Test("Initials are the first letter of each name, and never invented")
    func initials() {
        #expect(ProfilePicture.initials(first: "François", last: "Rousselet") == "FR")
        #expect(ProfilePicture.initials(first: "ada", last: "lovelace") == "AL")
        // One name gives one letter rather than two of the same one.
        #expect(ProfilePicture.initials(first: "Prince", last: "") == "P")
        #expect(ProfilePicture.initials(first: "  ", last: "  ") == nil)
        #expect(ProfilePicture.initials(first: "", last: "") == nil)
    }

    // MARK: - What is kept

    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        return Preferences(cloud: nil, local: defaults)
    }

    @Test("A name and a face are remembered, and can be taken back")
    func remembered() throws {
        let store = preferences()

        #expect(store.firstName.isEmpty)
        #expect(store.lastName.isEmpty)
        #expect(store.picture == nil)

        store.firstName = "Ada"
        store.lastName = "Lovelace"
        let scaled = try #require(ProfilePicture.scaled(try photograph()))
        store.picture = scaled

        #expect(store.firstName == "Ada")
        #expect(store.lastName == "Lovelace")
        #expect(store.picture == scaled)

        store.picture = nil
        #expect(store.picture == nil)
    }

    @Test("A picture that was never scaled is not kept")
    func oversized() throws {
        let store = preferences()
        // Straight from a camera, which is what the store must never hold.
        store.picture = try photograph(side: 2400)

        #expect(store.picture == nil)
    }
}

/// The window's own end of it : what the toolbar draws comes from here.
@Suite("The reader, as the window has them", .serialized)
@MainActor
struct ReaderProfileTests {
    private func window() throws -> (AppModel, Preferences) {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        let preferences = Preferences(cloud: nil, local: defaults)
        return (AppModel(database: try AppDatabase.inMemory(), preferences: preferences), preferences)
    }

    @Test("A name typed once is a name every section shows")
    func naming() throws {
        let (model, preferences) = try window()

        #expect(model.name == nil)
        #expect(model.initials == nil)

        model.firstName = "Ada"
        model.lastName = "Lovelace"

        #expect(model.name == "Ada Lovelace")
        #expect(model.initials == "AL")
        // And it outlives the window it was typed in.
        #expect(preferences.firstName == "Ada")
        #expect(preferences.lastName == "Lovelace")
    }

    @Test("A picture is scaled on its way in, and given back ready to draw")
    func picture() throws {
        let (model, preferences) = try window()
        #expect(model.picture == nil)

        let photograph = try ProfileTests().photograph()
        #expect(model.setPicture(photograph))

        let kept = try #require(preferences.picture)
        #expect(kept.count <= Preferences.pictureLimit)
        #expect(kept.count < photograph.count)
        let drawn = try #require(model.picture)
        #expect(max(drawn.width, drawn.height) == ProfilePicture.side)

        model.setPicture(nil)
        #expect(model.picture == nil)
        #expect(preferences.picture == nil)
    }

    @Test("What is not an image changes nothing")
    func refusal() throws {
        let (model, preferences) = try window()
        #expect(model.setPicture(photographOfNothing) == false)
        #expect(model.picture == nil)
        #expect(preferences.picture == nil)
    }

    private var photographOfNothing: Data { Data("not a photograph".utf8) }
}
