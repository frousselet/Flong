//
//  PlaceSuggestions.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import MapKit
import OSLog

/// One town MapKit is offering, as the reader types.
///
/// It carries the completion it came from rather than only the two lines it
/// shows : the completion is what a search is started from afterwards, and the
/// two lines are for display and are not an address.
nonisolated struct PlaceSuggestion: Identifiable {
    let completion: MKLocalSearchCompletion

    /// The completion object itself, which MapKit hands out once per result.
    var id: ObjectIdentifier { ObjectIdentifier(completion) }
    var title: String { completion.title }
    var subtitle: String { completion.subtitle }
}

/// What MapKit offers while the reader types the name of a town.
///
/// **The completer, and not a search per keystroke.** `MKLocalSearchCompleter`
/// exists for exactly this : it is cheap, it is what Apple asks be used while
/// somebody is typing, and running a full search on every letter would spend a
/// rate limit on nine answers the reader never looked at. The full search is
/// run once, on the one suggestion they chose.
///
/// **It only offers places, and only coarse ones.** The result type is an
/// address rather than a point of interest, and the address filter allows a
/// town, a district, a region and a country and nothing finer, so a reader
/// typing `Bar` is offered Barcelona and never a bar around the corner. The
/// question is where they read from, and a street is not an answer to it.
///
/// **Choosing is what resolves.** A completion is two lines of text with no
/// structure in it : `Paris` and `Île-de-France, France` are strings, and
/// taking the second half of the second line for a country would be reading
/// tea leaves. ``place(of:)`` asks MapKit for the item behind the suggestion
/// and takes the town and the country it names, which are fields. Nothing is
/// deduced from a display string.
@Observable
final class PlaceSuggestions: NSObject, MKLocalSearchCompleterDelegate {
    /// What is on offer right now, for the list to draw.
    private(set) var suggestions: [PlaceSuggestion] = []

    /// Whether MapKit has yet to answer the fragment last given to it.
    ///
    /// The screen needs it to know the difference between "there is no such
    /// town" and "nobody has answered yet" : without it, every first letter
    /// typed would be met with an empty list saying there is nothing.
    private(set) var isLooking = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(
            including: [.country, .administrativeArea, .subAdministrativeArea, .locality, .subLocality]
        )
        completer.delegate = self
    }

    /// Asks for what could be meant by what has been typed so far.
    ///
    /// An empty field asks for nothing rather than for everything : the
    /// completer is stopped and the list emptied, so a reader who cleared the
    /// field is not left looking at the answers to a question they took back.
    func look(for fragment: String) {
        let asked = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else {
            completer.cancel()
            suggestions = []
            isLooking = false
            return
        }
        isLooking = true
        completer.queryFragment = asked
    }

    /// Turns the suggestion the reader chose into a town and a country.
    ///
    /// Nothing at all when MapKit knows the suggestion but can say nothing
    /// structured about it, which the screen reports rather than papering over
    /// with the display strings.
    func place(of suggestion: PlaceSuggestion) async -> Place? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        do {
            let found = try await search.start()
            guard let address = found.mapItems.first?.addressRepresentations else { return nil }
            return Place(
                city: address.cityName,
                country: address.regionName,
                countryCode: address.region?.identifier
            )
        } catch {
            Log.place.error("A chosen town could not be resolved : \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - What MapKit says back

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.map(PlaceSuggestion.init)
        isLooking = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        // Nothing to show and nothing to say : a completer fails on a fragment
        // it cannot serve and on every keystroke made offline, and an alert per
        // letter would be the worst answer to either. The list keeps what it
        // had, which is the last thing that was true.
        isLooking = false
        Log.place.debug("MapKit had nothing to suggest : \(error, privacy: .public)")
    }
}
