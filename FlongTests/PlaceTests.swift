//
//  PlaceTests.swift
//  FlongTests
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// Where the reader says they are.
///
/// MapKit is not tested here and could not be : a completer needs a network and
/// a fix needs somebody standing somewhere, and neither is where the mistakes
/// are. What is worth proving is what is made of an answer : what is kept, what
/// is refused, that it survives the window it was chosen in, and that a refusal
/// leaves what the reader chose by hand alone.
@Suite("Where the reader is")
struct PlaceTests {
    @Test("A town and a country are taken as given, once trimmed")
    func plain() throws {
        let place = try #require(Place(city: " Paris ", country: "France\n", countryCode: "fr"))

        #expect(place.city == "Paris")
        #expect(place.country == "France")
        // Upper case, since it is the half that is matched on rather than read.
        #expect(place.countryCode == "FR")
        #expect(place.line == "Paris, France")
    }

    @Test("One of the two names is enough, and neither is not")
    func halves() throws {
        // A fix at sea has a country and no town.
        let country = try #require(Place(city: nil, country: "France"))
        #expect(country.city.isEmpty)
        #expect(country.line == "France")

        let city = try #require(Place(city: "Paris", country: nil))
        #expect(city.country.isEmpty)
        #expect(city.line == "Paris")

        #expect(Place(city: nil, country: nil) == nil)
        #expect(Place(city: "", country: "  ") == nil)
        // A code alone is not a place : it names one nobody was told about.
        #expect(Place(city: " ", country: nil, countryCode: "FR") == nil)
    }

    @Test("A country code that is not one is dropped rather than kept")
    func codes() throws {
        #expect(try #require(Place(city: "Paris", country: "France", countryCode: "FRA")).countryCode == nil)
        #expect(try #require(Place(city: "Paris", country: "France", countryCode: "F")).countryCode == nil)
        #expect(try #require(Place(city: "Paris", country: "France", countryCode: "1F")).countryCode == nil)
        #expect(try #require(Place(city: "Paris", country: "France", countryCode: "")).countryCode == nil)
        #expect(try #require(Place(city: "Paris", country: "France")).countryCode == nil)
    }

    // MARK: - What is kept

    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        return Preferences(cloud: nil, local: defaults)
    }

    @Test("A place is remembered whole, and can be taken back")
    func remembered() throws {
        let store = preferences()
        #expect(store.place == nil)

        store.place = Place(city: "Lyon", country: "France", countryCode: "FR")
        #expect(store.place == Place(city: "Lyon", country: "France", countryCode: "FR"))

        store.place = nil
        #expect(store.place == nil)
    }

    @Test("A place chosen without a code does not keep the last one")
    func codeIsNotStale() throws {
        let store = preferences()

        store.place = Place(city: "Lyon", country: "France", countryCode: "FR")
        // Somewhere MapKit named without a code : the old one has to go with
        // the old town, or Lisbon ends up filed under France.
        store.place = Place(city: "Lisbon", country: "Portugal")

        #expect(store.place?.city == "Lisbon")
        #expect(store.place?.countryCode == nil)
    }
}

/// The window's own end of it : the button, and what a refusal does.
@Suite("The reader's place, as the window has it", .serialized)
@MainActor
struct ReaderPlaceTests {
    private func window(
        _ locator: MemoryLocator = MemoryLocator()
    ) throws -> (AppModel, Preferences) {
        let defaults = UserDefaults(suiteName: "com.rslt.Flong.tests.\(UUID().uuidString)")!
        let preferences = Preferences(cloud: nil, local: defaults)
        let model = AppModel(
            database: try AppDatabase.inMemory(),
            preferences: preferences,
            locator: locator
        )
        return (model, preferences)
    }

    @Test("A place chosen once outlives the window it was chosen in")
    func chosen() throws {
        let (model, preferences) = try window()
        #expect(model.place == nil)

        model.setPlace(Place(city: "Paris", country: "France", countryCode: "FR"))

        #expect(model.place?.line == "Paris, France")
        #expect(preferences.place?.countryCode == "FR")

        model.setPlace(nil)
        #expect(model.place == nil)
        #expect(preferences.place == nil)
    }

    @Test("The device's answer is kept, and nothing is reported")
    func located() async throws {
        let found = try #require(Place(city: "Lyon", country: "France", countryCode: "FR"))
        let locator = MemoryLocator(.success(found))
        let (model, preferences) = try window(locator)

        #expect(await model.locate() == nil)

        #expect(locator.asked == 1)
        #expect(model.place == found)
        #expect(preferences.place == found)
        #expect(!model.isLocating)
    }

    @Test("A refusal is handed back, and leaves what the reader chose alone")
    func refused() async throws {
        let locator = MemoryLocator(.failure(.refused))
        let (model, preferences) = try window(locator)

        let chosen = try #require(Place(city: "Paris", country: "France", countryCode: "FR"))
        model.setPlace(chosen)

        #expect(await model.locate() == .refused)

        // What they answered by hand stands : the system declining to answer is
        // not the reader taking their own answer back.
        #expect(model.place == chosen)
        #expect(preferences.place == chosen)
        // And nothing goes to the shell's alert, which is two sheets away.
        #expect(model.failure == nil)
    }

    @Test("A fix that comes to nothing says so, and asks for a search instead")
    func unavailable() async throws {
        let (model, _) = try window(MemoryLocator(.failure(.unavailable)))

        #expect(await model.locate() == .unavailable)
        #expect(model.place == nil)
    }
}
