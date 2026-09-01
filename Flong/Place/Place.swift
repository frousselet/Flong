//
//  Place.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where the reader is, as coarsely as a reader would say it out loud.
///
/// **A city and a country, and never a coordinate.** What a later feature needs
/// is the region somebody reads from, which is a town and the country it is in ;
/// a latitude to five decimal places is their street, it would travel to their
/// iCloud with the rest of their preferences, and nothing planned would ever
/// read it. A fix taken from the device is turned into this and thrown away in
/// the same breath, which is why ``Locating`` hands back a place rather than a
/// location.
///
/// **The country code is kept beside the country's name because they answer
/// different questions.** The name is what the reader is shown and is in
/// whatever language they read in ; the code is what a rule or a query would
/// match on, and `FR` stays `FR` on a device set to English. Keeping only the
/// name would mean matching on a translated string, which is how a preference
/// set on one device stops working on the next.
///
/// One of the two names may be missing and never both : a fix in the middle of
/// the North Sea has a country and no town, and a place with neither is not a
/// place. That is what makes the initializer failable.
nonisolated struct Place: Hashable, Sendable {
    /// The town, as MapKit named it. Empty where there is none.
    let city: String
    /// The country, in the reader's own language. Empty where there is none.
    let country: String
    /// ISO 3166-1 alpha-2, upper case, when one was given.
    let countryCode: String?

    /// Takes what a search or a fix said, and keeps it only if it says
    /// something.
    ///
    /// Everything is trimmed, since a name arrives from a service and a service
    /// pads. A code that is not two letters is dropped rather than kept as a
    /// third spelling of the country : it is only worth having if it is the one
    /// thing that never changes.
    init?(city: String?, country: String?, countryCode: String? = nil) {
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !city.isEmpty || !country.isEmpty else { return nil }

        self.city = city
        self.country = country

        let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let isAlpha2 = code.count == 2 && code.allSatisfy { $0.isLetter && $0.isASCII }
        self.countryCode = isAlpha2 ? code : nil
    }

    /// The one line a row shows : `Paris, France`.
    ///
    /// A comma and a space rather than a translated joiner. It is how an
    /// address is written in both languages Flong speaks, and the two halves
    /// are proper nouns that are not being made into a sentence.
    var line: String {
        [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
