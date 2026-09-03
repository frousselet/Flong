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
        static let theme = "interface.theme"
        static let firstName = "reader.first-name"
        static let lastName = "reader.last-name"
        static let picture = "reader.picture"
        static let city = "reader.city"
        static let country = "reader.country"
        static let countryCode = "reader.country-code"
        static let device = "device.identifier"
        static let newStoryNotices = "notify.new-stories"
        static let newArticleNotices = "notify.new-articles"
        static let storiesAnnouncedAt = "notify.stories-announced-at"
        static let articlesAnnouncedAt = "notify.articles-announced-at"
        static let collaborationNotices = "notify.collaborations"
        static let mutedCollections = "notify.muted-collections"
        static let collaborationsAnnouncedAt = "notify.collaborations-announced-at"
        static let recentSearches = "search.recent"
        static let poolContributes = "pool.contributes"
        static let poolIdentifier = "pool.identifier"

        /// Every key, for the one operation that has to name all of them.
        static let all = [
            articleBody, theme, firstName, lastName, picture, city, country, countryCode, device,
            newStoryNotices, newArticleNotices, storiesAnnouncedAt, articlesAnnouncedAt, collaborationNotices,
            mutedCollections, collaborationsAnnouncedAt, recentSearches,
            poolContributes, poolIdentifier,
        ]
    }

    /// How many searches are remembered.
    ///
    /// Ten, which is about what a page can offer without becoming a log of
    /// everything the reader has ever wondered. Past that the eleventh is
    /// dropped rather than the list growing : a preference store of one
    /// megabyte is not a place to keep a history.
    static let recentSearchLimit = 10

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

    /// How the whole application is set : the faces and the colours.
    ///
    /// Carried between the devices, for the same reason the body an article
    /// opens on is : it is a decision the reader made about themselves and not
    /// about a device, and a reader who set their iPad to read on paper did not
    /// mean only on the iPad. The system's own appearance until they say
    /// otherwise, which is the one answer that cannot be wrong on a device they
    /// have never opened this panel on.
    ///
    /// A value nobody recognizes falls back to the standard theme rather than
    /// to nothing : it is what a newer version writing a fourth theme would
    /// leave behind on an older one, and an application that refused to draw
    /// itself over a preference would be worse than one drawn plainly.
    var theme: Theme {
        get { value(for: Key.theme).flatMap(Theme.init(rawValue:)) ?? .standard }
        set { set(newValue.rawValue, for: Key.theme) }
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

    /// Where the reader reads from, when they have said.
    ///
    /// **Three keys and not one encoded blob.** A town, a country and a country
    /// code are three strings, the store holds strings, and a JSON payload in a
    /// preference is a thing that has to be versioned the first time a field is
    /// added to it. Written and removed together, so a half-written place is
    /// never read back.
    ///
    /// It travels with the name and the face, for the same reason and to the
    /// same place : it is a fact about the reader rather than about a device,
    /// and a reader who said Paris on the phone did not mean only on the phone.
    /// Nothing else is ever told : section 20 says no data leaves the device,
    /// and where somebody lives is not an exception to that.
    var place: Place? {
        get {
            Place(
                city: value(for: Key.city),
                country: value(for: Key.country),
                countryCode: value(for: Key.countryCode)
            )
        }
        set {
            guard let newValue else {
                for key in [Key.city, Key.country, Key.countryCode] { remove(key) }
                return
            }
            set(newValue.city, for: Key.city)
            set(newValue.country, for: Key.country)
            if let code = newValue.countryCode {
                set(code, for: Key.countryCode)
            } else {
                remove(Key.countryCode)
            }
        }
    }

    // MARK: - What the reader wants to be told

    /// Whether the reader wants to hear about a story that has just opened.
    ///
    /// **Carried between the devices, unlike the permission.** What the reader
    /// wants to be told is a decision about themselves and belongs on all their
    /// devices ; whether a given device may interrupt them is the system's
    /// answer on that device, asked for separately and never travelling. The
    /// two are different questions and it is right that they disagree : a
    /// reader may want the notices and have refused them on the Mac.
    ///
    /// Off until the reader says otherwise. Turning it on is what asks the
    /// system, which is the only honest moment to ask.
    var wantsNewStoryNotices: Bool {
        get { flag(for: Key.newStoryNotices) }
        set { set(newValue, for: Key.newStoryNotices) }
    }

    /// Whether the reader wants to hear about every article their sources
    /// publish, whatever the source.
    ///
    /// **The one switch a reader arrives looking for.** Asking about a source
    /// at a time is the finer instrument and it stays, on the source itself ;
    /// but a reader who follows thirty feeds and wants to know when any of them
    /// publishes was being asked to make thirty decisions to say one thing. The
    /// two live together : this covers every source, and the switch on a source
    /// covers that one when this is off.
    ///
    /// Off until the reader says otherwise, like every other switch, and
    /// carried between their devices because it is a decision about themselves.
    var wantsNewArticleNotices: Bool {
        get { flag(for: Key.newArticleNotices) }
        set { set(newValue, for: Key.newArticleNotices) }
    }

    /// Whether the reader wants to hear when somebody adds to a collection they
    /// share.
    ///
    /// Off until they say otherwise, like every other switch in that panel, and
    /// carried between their devices for the same reason : it is a decision
    /// about themselves and not about a device.
    ///
    /// **A collaboration is the one thing here somebody else caused.** Every
    /// other notice Flong may post is about something it worked out on its own
    /// from feeds nobody else touched ; this one is a person doing something,
    /// which is exactly why a reader may want it and exactly why they may want
    /// it only for some collections. See ``mutedSharedCollections``.
    var wantsCollaborationNotices: Bool {
        get { flag(for: Key.collaborationNotices) }
        set { set(newValue, for: Key.collaborationNotices) }
    }

    /// The shared collections the reader has asked to hear nothing about.
    ///
    /// **A list of the quiet ones rather than of the loud ones.** A reader who
    /// turns the switch on means the collections they are in, including the
    /// ones they have not been invited to yet ; storing the opposite would have
    /// every new collection arrive silent and look broken.
    ///
    /// By zone, because that is what a shared collection is. A name would go
    /// wrong the moment two people called theirs the same thing.
    /// **Written locally as well as to iCloud**, like every other preference
    /// here : a reader with no iCloud account is a reader section 3 says the
    /// application is fully usable for, and a switch that did nothing at all
    /// for them would be a switch that lied.
    var mutedSharedCollections: Set<String> {
        get {
            if let cloud, let carried = cloud.array(forKey: Key.mutedCollections) as? [String] {
                return Set(carried)
            }
            return Set(local.array(forKey: Key.mutedCollections) as? [String] ?? [])
        }
        set {
            let names = Array(newValue).sorted()
            local.set(names, forKey: Key.mutedCollections)
            cloud?.set(names, forKey: Key.mutedCollections)
            cloud?.synchronize()
        }
    }

    /// The last moment this device said anything about a collaboration.
    ///
    /// Local and never carried, for the same reason the story watermark is not :
    /// each device tells its own reader, and a watermark that travelled would
    /// have the second device stay silent about what only the first announced.
    var collaborationsAnnouncedAt: Date? {
        get { local.object(forKey: Key.collaborationsAnnouncedAt) as? Date }
        set {
            guard let newValue else {
                local.removeObject(forKey: Key.collaborationsAnnouncedAt)
                return
            }
            local.set(newValue, forKey: Key.collaborationsAnnouncedAt)
        }
    }

    /// The last moment this device said anything about a new story.
    ///
    /// Local and never carried, for the same reason the device identifier is :
    /// each device tells its own reader, and a watermark that travelled would
    /// have the second device stay silent about what only the first announced.
    ///
    /// Nothing at all means nothing to announce. It is stamped when the reader
    /// turns the notices on, so the stories that were already open that day are
    /// not news.
    var storiesAnnouncedAt: Date? {
        get { local.object(forKey: Key.storiesAnnouncedAt) as? Date }
        set {
            guard let newValue else {
                local.removeObject(forKey: Key.storiesAnnouncedAt)
                return
            }
            local.set(newValue, forKey: Key.storiesAnnouncedAt)
        }
    }

    /// The last moment this device said anything about an article one of the
    /// reader's own sources published.
    ///
    /// Local and never carried, like the other two watermarks and for the same
    /// reason : each device tells its own reader, and one that travelled would
    /// have the second device stay silent about what only the first announced.
    ///
    /// **Which sources those are is not here.** That is written on the sources
    /// themselves, where a decision about a publisher belongs, and it travels
    /// with them ; this is only how far this device has got through telling the
    /// reader about them.
    ///
    /// Nothing at all means nothing to announce. It is stamped the moment the
    /// reader asks about their first source, so what that source published
    /// before they asked is not news.
    var articlesAnnouncedAt: Date? {
        get { local.object(forKey: Key.articlesAnnouncedAt) as? Date }
        set {
            guard let newValue else {
                local.removeObject(forKey: Key.articlesAnnouncedAt)
                return
            }
            local.set(newValue, forKey: Key.articlesAnnouncedAt)
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

    // MARK: - The common pool

    /// Whether the reader offers what they follow to the other readers.
    ///
    /// **Three answers and not two.** `nil` is *nobody has asked yet*, and it
    /// is what makes the question of section 8 askable once rather than every
    /// time : a reader who said no is not asked again, and a reader who has
    /// never seen the page has not said no. Reading a plain flag would make
    /// those two the same answer and would turn the question into a nag.
    ///
    /// Carried between the reader's devices, like every other decision about
    /// themselves : somebody who said yes on their phone did not mean only on
    /// their phone.
    var contributesToPool: Bool? {
        get {
            if let cloud, cloud.object(forKey: Key.poolContributes) != nil {
                return cloud.bool(forKey: Key.poolContributes)
            }
            guard local.object(forKey: Key.poolContributes) != nil else { return nil }
            return local.bool(forKey: Key.poolContributes)
        }
        set {
            guard let newValue else { return remove(Key.poolContributes) }
            set(newValue, for: Key.poolContributes)
        }
    }

    /// What this reader's records in the pool are named after.
    ///
    /// **Made here and never derived from their iCloud identity.** A record
    /// name in a database the whole world reads should say nothing about who
    /// wrote it, and a name nobody can work out in advance is also a name
    /// nobody can take first to stop somebody publishing.
    ///
    /// Carried between the reader's devices, so that their iPad rewrites the
    /// list their phone published rather than opening a second one, which would
    /// be one person counted twice by nobody, since the counting is by iCloud
    /// identity, and two records where one would do.
    var poolIdentifier: UUID {
        if let existing = cloud?.string(forKey: Key.poolIdentifier).flatMap(UUID.init(uuidString:)) {
            local.set(existing.uuidString, forKey: Key.poolIdentifier)
            return existing
        }
        if let existing = local.string(forKey: Key.poolIdentifier).flatMap(UUID.init(uuidString:)) {
            cloud?.set(existing.uuidString, forKey: Key.poolIdentifier)
            cloud?.synchronize()
            return existing
        }

        let made = UUID()
        set(made.uuidString, for: Key.poolIdentifier)
        return made
    }

    // MARK: - What the reader looked for

    /// The queries the reader last ran, newest first.
    ///
    /// **Carried between the devices**, like everything else the reader
    /// decided. A query in this application is not a word typed into a box, it
    /// is a sentence in the language of section 12 with fields, states and
    /// dates in it, and a reader who worked one out on the Mac should not have
    /// to work it out again on the phone.
    ///
    /// Capped at ``recentSearchLimit`` on the way in rather than on the way
    /// out, so the store never holds more than is ever shown.
    var recentSearches: [String] {
        get {
            if let cloud, let carried = cloud.array(forKey: Key.recentSearches) as? [String] {
                return carried
            }
            return local.array(forKey: Key.recentSearches) as? [String] ?? []
        }
        set {
            let kept = Array(newValue.prefix(Self.recentSearchLimit))
            local.set(kept, forKey: Key.recentSearches)
            cloud?.set(kept, forKey: Key.recentSearches)
            cloud?.synchronize()
        }
    }

    // MARK: - Starting over

    /// Forgets every choice the reader ever made, here and in their iCloud.
    ///
    /// Every key this type owns, and only those : the store belongs to the
    /// whole system and a reset of Flong is not a reason to touch what anybody
    /// else put in it.
    ///
    /// **The device identifier goes too.** It is an identifier, and a reset
    /// that left one behind would not be one. The archive folder it named is
    /// deleted in the same pass, so nothing is orphaned by the new name this
    /// device will give itself.
    func forgetEverything() {
        for key in Key.all {
            local.removeObject(forKey: key)
            cloud?.removeObject(forKey: key)
        }
        cloud?.synchronize()
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

    private func remove(_ key: String) {
        local.removeObject(forKey: key)
        cloud?.removeObject(forKey: key)
        cloud?.synchronize()
    }

    /// A yes or a no, taking iCloud's answer when iCloud has one.
    ///
    /// The presence of the key is what is asked, not its value : `bool(forKey:)`
    /// answers `false` for a key nobody ever wrote, so reading it directly would
    /// have an empty iCloud store overrule a `true` written here.
    private func flag(for key: String) -> Bool {
        if let cloud, cloud.object(forKey: key) != nil { return cloud.bool(forKey: key) }
        return local.bool(forKey: key)
    }

    private func set(_ value: Bool, for key: String) {
        local.set(value, forKey: key)
        cloud?.set(value, forKey: key)
        cloud?.synchronize()
    }
}
