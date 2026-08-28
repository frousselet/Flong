//
//  GReaderDTO.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Accepts an integer sent either as a JSON number or as a string.
///
/// FreshRSS is not consistent : `unread-count` sends `count` as a number and
/// `newestItemTimestampUsec` as a string, and other servers differ again.
nonisolated struct LooseInt: Decodable, Sendable, Equatable {
    let value: Int

    init(_ value: Int) { self.value = value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else if let string = try? container.decode(String.self), let int = Int(string) {
            value = int
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an integer")
        }
    }
}

/// Wire shapes of the Google Reader JSON responses.
///
/// Field names and optionality are taken from FreshRSS 1.29.1 : `tagList`,
/// `subscriptionList`, `unreadCount` and `streamContents` in `p/api/greader.php`,
/// and `FreshRSS_Entry::toGReader` in `app/Models/Entry.php`.
nonisolated enum GReaderDTO {
    struct SubscriptionList: Decodable, Sendable {
        let subscriptions: [Subscription]
    }

    /// `id` is `feed/<numeric identifier>`, never `feed/<url>` : the feed URL is
    /// carried separately by `url`.
    struct Subscription: Decodable, Sendable {
        let id: String
        let title: String?
        /// URL of the feed document.
        let url: String?
        /// URL of the site the feed belongs to.
        let htmlUrl: String?
        let iconUrl: String?
        /// FreshRSS puts a feed in exactly one category, so this holds zero or one entry.
        let categories: [SubscriptionCategory]?
    }

    struct SubscriptionCategory: Decodable, Sendable {
        let id: String
        let label: String?
    }

    struct TagList: Decodable, Sendable {
        let tags: [Tag]
    }

    /// FreshRSS returns three kinds of entry : the built-in states, which carry no
    /// `type`, the folders, typed `folder`, and the article labels, typed `tag`.
    /// Folders and labels share the `user/-/label/` prefix, so `type` is the only
    /// way to tell them apart.
    struct Tag: Decodable, Sendable {
        let id: String
        let type: String?
        let unreadCount: LooseInt?

        private enum CodingKeys: String, CodingKey {
            case id
            case type
            case unreadCount = "unread_count"
        }
    }

    struct UnreadCountList: Decodable, Sendable {
        let max: LooseInt?
        let unreadcounts: [UnreadCount]
    }

    /// Reported per feed, per folder, per label, plus a total under the
    /// reading-list identifier.
    struct UnreadCount: Decodable, Sendable {
        let id: String
        let count: LooseInt
        let newestItemTimestampUsec: String?
    }

    struct StreamContents: Decodable, Sendable {
        let id: String?
        /// Present only when the page was filled, absent on the last page.
        let continuation: String?
        let items: [Item]
    }

    struct Item: Decodable, Sendable {
        /// Long form, `tag:google.com,2005:reader/item/<16 hexadecimal digits>`.
        let id: String
        let title: String?
        let author: String?
        /// Publication date, in seconds since the epoch.
        let published: LooseInt?
        /// Sent by servers other than FreshRSS, which omits it.
        let updated: LooseInt?
        /// Crawl date in milliseconds, as a string.
        let crawlTimeMsec: String?
        /// Crawl date in microseconds, as a string. Doubles as the article's decimal identifier.
        let timestampUsec: String?
        /// FreshRSS serializes in compatibility mode, where the body lands here
        /// and `content` is absent. Other servers use `content` for the full body.
        let summary: ItemContent?
        let content: ItemContent?
        let canonical: [Link]?
        let alternate: [Link]?
        /// Holds the reading-list marker, the folder label, the read and starred
        /// states, and any article label.
        let categories: [String]?
        let origin: Origin?
    }

    struct ItemContent: Decodable, Sendable {
        let content: String?
    }

    struct Link: Decodable, Sendable {
        let href: String?
    }

    struct Origin: Decodable, Sendable {
        /// `feed/<numeric identifier>`, matching `Subscription.id`.
        let streamId: String?
        let title: String?
        let htmlUrl: String?
    }
}
