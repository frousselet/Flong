//
//  Preferences.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog

/// What the reader has chosen, carried between their devices.
///
/// **`NSUbiquitousKeyValueStore` rather than CloudKit.** Section 8 gives the
/// private database a budget of around three thousand records, and it is spent
/// on subscriptions, kept articles and read states. A handful of preferences has
/// no business in it : Apple provides a key-value store for exactly this, one
/// megabyte and a thousand keys, synchronized for free and counting against
/// nothing.
///
/// **A local copy is written too.** The iCloud store does nothing at all without
/// an account, and a reader with no iCloud is a reader Flong works perfectly
/// well for : section 3 says so. The local copy is what they get, and it is also
/// what answers on the first launch after an install, before iCloud has said
/// anything.
///
/// Reads take the iCloud value when there is one, since that is the one another
/// device may have changed.
///
/// **On `@unchecked`.** Both stores are documented as safe to use from any
/// thread and neither says so in its type. The claim rests on Apple's
/// documentation rather than on the compiler, which is what `@unchecked` is
/// admitting rather than hiding.
nonisolated final class Preferences: @unchecked Sendable {
    /// Which body an article opens on.
    nonisolated enum ArticleBody: String, Hashable, Sendable, CaseIterable {
        /// What the feed sent, which is what the publisher chose to send.
        case feed
        /// The whole article, fetched from the page behind it.
        case page
    }

    private enum Key {
        static let articleBody = "article.body"
        static let firstName = "reader.first-name"
        static let lastName = "reader.last-name"
        static let picture = "reader.picture"
        static let device = "device.identifier"
    }

    /// The largest picture that may be kept.
    ///
    /// The key-value store holds one megabyte in all, and everything else the
    /// reader has chosen has to fit beside this. A picture scaled down to the
    /// size it is shown at comes in well under this ; anything that does not is
    /// a picture that was not scaled, and it is refused rather than quietly
    /// filling the store.
    static let pictureLimit = 128 * 1024

    private let cloud: NSUbiquitousKeyValueStore?
    private let local: UserDefaults

    init(cloud: NSUbiquitousKeyValueStore? = .default, local: UserDefaults = .standard) {
        self.cloud = cloud
        self.local = local
    }

    /// Asks iCloud for what the reader's other devices have said.
    ///
    /// The answer arrives later, through a notification : this only asks.
    func synchronize() {
        cloud?.synchronize()
    }

    var articleBody: ArticleBody {
        get { value(for: Key.articleBody).flatMap(ArticleBody.init(rawValue:)) ?? .feed }
        set { set(newValue.rawValue, for: Key.articleBody) }
    }

    // MARK: - Who is reading

    /// The reader's own name and face, which belong to nobody else.
    ///
    /// They are the reader's, kept in the reader's own iCloud, and Flong has no
    /// account to attach them to and nowhere to send them : section 3 says
    /// there is no server, and a name typed into a feed reader is not an
    /// exception to that. They are here so that a device the reader picks up
    /// looks like theirs, and for nothing else.
    var firstName: String {
        get { value(for: Key.firstName) ?? "" }
        set { set(newValue, for: Key.firstName) }
    }

    var lastName: String {
        get { value(for: Key.lastName) ?? "" }
        set { set(newValue, for: Key.lastName) }
    }

    var picture: Data? {
        get { cloud?.data(forKey: Key.picture) ?? local.data(forKey: Key.picture) }
        set {
            guard let newValue else {
                local.removeObject(forKey: Key.picture)
                cloud?.removeObject(forKey: Key.picture)
                cloud?.synchronize()
                return
            }
            guard newValue.count <= Self.pictureLimit else {
                Log.store.error("A profile picture of \(newValue.count) bytes was not kept : it was never scaled.")
                return
            }
            local.set(newValue, forKey: Key.picture)
            cloud?.set(newValue, forKey: Key.picture)
            cloud?.synchronize()
        }
    }

    /// What this device calls itself in the shared archive.
    ///
    /// Local and never carried to iCloud, which is the point of it : every
    /// device needs a different one, and a value that travelled would give them
    /// all the same name and have each of them write over the others' files.
    var device: String {
        if let existing = local.string(forKey: Key.device) { return existing }

        let made = UUID().uuidString
        local.set(made, forKey: Key.device)
        return made
    }

    // MARK: - Both stores

    private func value(for key: String) -> String? {
        cloud?.string(forKey: key) ?? local.string(forKey: key)
    }

    private func set(_ value: String, for key: String) {
        local.set(value, forKey: key)
        cloud?.set(value, forKey: key)
        cloud?.synchronize()
    }
}
