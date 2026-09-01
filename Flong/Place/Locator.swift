//
//  Locator.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreLocation
import Foundation
import MapKit
import OSLog

/// Why choosing a place did not end in one.
///
/// **Three answers and not one**, because there are three different things for
/// the reader to do about it : go to the system settings, type the name of
/// their town, or pick a different one. A single "it did not work" would leave
/// them with none of those.
///
/// Each carries its own sentence, as ``AppFailure`` does, because the screen
/// that asked is the screen that says so : the shell's alert is behind two
/// sheets by then, and an alert presented from under a sheet is an alert
/// nobody sees.
nonisolated enum PlaceFailure: Error, Hashable, Identifiable, Sendable {
    /// The reader said no, or the system says no on their behalf.
    case refused
    /// No fix came, or nothing recognizable stands at the one that did.
    case unavailable
    /// MapKit offered a town and then could say nothing structured about it.
    case unreadable

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .refused: "Flong may not use your location. The system settings are where that is changed."
        case .unavailable: "Where you are could not be worked out. Search for your city instead."
        case .unreadable: "That town could not be read. Try another one."
        }
    }
}

/// Asks the device where it is, and answers with a town.
///
/// A protocol so the window can be driven by a test : there is no fix in a test
/// runner and no reader to grant anything, and what is worth checking is what
/// the window does with an answer rather than that CoreLocation works.
protocol Locating {
    func here() async throws -> Place
}

/// The device's own answer : one fix, turned into a town, and forgotten.
///
/// **It asks once and stops.** Nothing here follows the reader : the question
/// is which town they read from, it is answered once when they press the
/// button, and a stream left running would be a feed reader watching somebody
/// move. `CLLocationUpdate.liveUpdates()` is the modern way to ask, and the
/// first update carrying a location ends it.
///
/// **The coordinate does not survive the call.** It is turned into a town and a
/// country by MapKit and dropped where it stands : what is kept is
/// ``Place``, which is what the reader would have typed themselves. Their
/// preferences travel to their iCloud, and a latitude has no business making
/// that trip.
///
/// **The permission is asked for at the moment the reader presses the button**,
/// which is the same rule the notices follow : a prompt at first launch is a
/// prompt about something nobody has seen yet, and that is how an application
/// gets refused for good. A refusal already given is thrown straight back
/// rather than waited on, since asking again does not prompt.
///
/// **There is a clock on it.** A device indoors, or one whose reader left the
/// prompt standing, can leave the stream silent for as long as it likes. Twenty
/// seconds is long enough for a cold fix and short enough that a spinner is not
/// a hang.
@MainActor
final class DeviceLocator: Locating {
    /// How long a fix is waited for before the button gives up.
    static let patience = Duration.seconds(20)

    /// Held rather than made and dropped : on iOS the prompt belongs to the
    /// manager that asked for it, and a manager released a line later takes its
    /// own prompt down with it.
    private var manager: CLLocationManager?

    /// Nonisolated so that the window can name it as a default argument, which
    /// is evaluated where the caller stands rather than on the main actor.
    /// Nothing is touched here : the manager is made at the first question.
    nonisolated init() {}

    func here() async throws -> Place {
        try ask()
        return try await place(at: try Self.fix())
    }

    /// Asks the system, when the system has not been asked yet.
    private func ask() throws {
        let manager = manager ?? CLLocationManager()
        self.manager = manager

        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .restricted, .denied: throw PlaceFailure.refused
        default: break
        }
    }

    /// One fix, or the clock.
    ///
    /// The two run against each other and the first to finish wins, which is
    /// also what cancels the other : a stream nobody is reading is a radio left
    /// on.
    private static func fix() async throws -> CLLocation {
        try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { try await waitForFix() }
            group.addTask {
                try await Task.sleep(for: patience)
                throw PlaceFailure.unavailable
            }

            guard let first = try await group.next() else { throw PlaceFailure.unavailable }
            group.cancelAll()
            return first
        }
    }

    /// The first update that carries a location, and what to make of the ones
    /// that do not.
    ///
    /// An update with no location is not a failure by itself : it is what
    /// arrives while the prompt is standing open and while the receiver is
    /// still working. Only a refusal and a flat "there is no location here" end
    /// it early ; everything else waits for the clock.
    private static func waitForFix() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw PlaceFailure.refused
            }
            if let location = update.location { return location }
            if update.locationUnavailable { throw PlaceFailure.unavailable }
        }
        throw PlaceFailure.unavailable
    }

    /// What stands at a coordinate, as coarsely as MapKit will say it.
    ///
    /// `MKReverseGeocodingRequest` rather than `CLGeocoder`, which is deprecated
    /// as of this year's systems, and the address representations rather than a
    /// formatted line : a town and a country are fields there, and a line would
    /// have to be taken apart to get them back.
    private func place(at location: CLLocation) async throws -> Place {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw PlaceFailure.unavailable
        }

        let items = try await request.mapItems
        guard let address = items.first?.addressRepresentations,
            let place = Place(
                city: address.cityName,
                country: address.regionName,
                countryCode: address.region?.identifier
            )
        else {
            Log.place.error("A fix came back, and nothing recognizable stands at it.")
            throw PlaceFailure.unavailable
        }

        return place
    }
}

/// What a test asks instead of the device.
///
/// The same bargain ``MemoryAnnouncer`` strikes : the system's own answer needs
/// a receiver, a permission and somebody standing somewhere, none of which a
/// test runner has, and none of which is where the mistakes are. What is worth
/// checking is what the window does with a place and with a refusal.
final class MemoryLocator: Locating {
    var answer: Result<Place, PlaceFailure>
    private(set) var asked = 0

    init(_ answer: Result<Place, PlaceFailure> = .failure(.unavailable)) {
        self.answer = answer
    }

    func here() async throws -> Place {
        asked += 1
        return try answer.get()
    }
}
