//
//  ArticleKeyTests.swift
//  FlongTests
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("The same article twice")
struct ArticleKeyTests {
    private let room = "leparisien.fr"

    private func key(_ address: String?, title: String = "Une nouvelle", published: Date? = nil) -> String? {
        ArticleKey.of(url: address.flatMap(URL.init(string:)), title: title, publishedAt: published, room: room)
    }

    @Test("One address written two ways is one article")
    func addresses() {
        let plain = key("https://www.leparisien.fr/societe/telephones-au-lycee-29-08-2026.php")
        let tracked = key(
            "https://leparisien.fr/societe/telephones-au-lycee-29-08-2026.php?utm_source=rss&utm_medium=feed"
        )
        let trailing = key("https://leparisien.fr/societe/telephones-au-lycee-29-08-2026.php/")
        let anchored = key("https://leparisien.fr/societe/telephones-au-lycee-29-08-2026.php#commentaires")

        #expect(plain == tracked)
        #expect(plain == trailing)
        #expect(plain == anchored)
    }

    @Test("A parameter that says what to read is kept")
    func meaningfulQuery() {
        // `?p=1234` is where the article is ; `?utm_source` is who sent us.
        #expect(key("https://example.com/index.php?p=1234") != key("https://example.com/index.php?p=1235"))
        #expect(
            key("https://example.com/index.php?p=1234&utm_campaign=x") == key("https://example.com/index.php?p=1234"))
    }

    @Test("Two articles at two addresses are two articles")
    func differentArticles() {
        #expect(key("https://leparisien.fr/a.php") != key("https://leparisien.fr/b.php"))
    }

    @Test("Without an address, a headline in one room on one day")
    func headlines() {
        let day = Date(timeIntervalSince1970: 1_787_646_600)
        let same = ArticleKey.of(url: nil, title: "L'interdiction des téléphones", publishedAt: day, room: room)
        let spelled = ArticleKey.of(url: nil, title: "L’interdiction des  Téléphones", publishedAt: day, room: room)

        #expect(same == spelled)
    }

    @Test("Two papers writing the same headline wrote two articles")
    func differentRooms() {
        let day = Date(timeIntervalSince1970: 1_787_646_600)
        let parisien = ArticleKey.of(url: nil, title: "L'interdiction des téléphones", publishedAt: day, room: room)
        let monde = ArticleKey.of(
            url: nil, title: "L'interdiction des téléphones", publishedAt: day, room: "lemonde.fr")

        // Collapsing these would destroy the one thing the digest is for.
        #expect(parisien != monde)
    }

    @Test("The same headline on another day is another article")
    func differentDays() {
        let day = Date(timeIntervalSince1970: 1_787_646_600)
        let later = day.addingTimeInterval(86400 * 2)

        #expect(
            ArticleKey.of(url: nil, title: "Le point de la semaine", publishedAt: day, room: room)
                != ArticleKey.of(url: nil, title: "Le point de la semaine", publishedAt: later, room: room)
        )
    }

    @Test("Nothing stable to go on is no key at all")
    func nothing() {
        #expect(ArticleKey.of(url: nil, title: "Une nouvelle", publishedAt: nil, room: nil) == nil)
        #expect(ArticleKey.of(url: nil, title: "   ", publishedAt: nil, room: room) == nil)
        #expect(ArticleKey.address(URL(string: "file:///tmp/a.html")) == nil)
    }
}
