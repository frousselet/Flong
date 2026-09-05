//
//  TopicFamily.swift
//  Flong
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What a subject is a kind of, and the colour every subject in it wears.
///
/// **Eight colours for fifty-two sections, because a colour per section is not
/// a code.** Fifty-two hues cannot be told apart, and a reader who has to
/// learn which of four blues is `Immigration` is reading a legend rather than a
/// page. Eight can be learnt without trying : the news of the state is blue,
/// money is teal, the living world green, the body red, ordinary life orange,
/// science violet, culture magenta, and the two sections that sort nothing wear
/// no colour at all.
///
/// **The colour is a second way of saying the mark, never the only way.** A
/// pill says its subject in words, and the glyph in front of the words says it
/// again in a shape ; the colour is a third telling of the same thing, for the
/// reader who is scanning rather than reading. Nothing on any page is said in
/// colour alone, which is what makes it safe to lose : a reader who cannot tell
/// the red from the green reads exactly the page everybody else does.
///
/// **One set for the three themes.** A hue restated per theme is twenty-four
/// colours to keep true and to check against six papers, for a page that would
/// not read differently ; these are muted enough to sit on white, on warm
/// paper and on Solarized's base3 alike, each at four and a half to one or
/// better against all three, which ``TopicColourTests`` is what holds them to.
///
/// **A family is reached through the mark and not through the name.** A subject
/// is stored as a string in the reader's own language, so a store carries
/// `Environnement` where another carries `Environment` and a lookup by name
/// answers for one reader and not the other. The mark is the same string
/// everywhere, and a subject the reader wrote themselves wears one from the
/// catalogue's own palette, so it takes the colour of the family whose glyph
/// they picked : a subject wearing a leaf is green without anybody deciding it.
nonisolated enum TopicFamily: String, Hashable, Sendable, CaseIterable {
    /// The news of the state : who governs, who judges, who is let in.
    case publicLife
    /// What is earned, spent, built and moved.
    case money
    /// The land and the sky, and what is done to them.
    case land
    /// The body, and the harm done to it.
    case body
    /// A life outside the news of the state : school, the table, faith, the
    /// road, the pitch.
    case everyday
    /// What is found out, and what is built out of it.
    case science
    /// What is written, filmed, played, worn and put up.
    case culture
    /// The two sections that sort nothing, and anything wearing a mark from no
    /// catalogue at all.
    case plain

    /// The colour, in one appearance.
    ///
    /// Stated as ``Ink`` like every other colour in the application, so a hue
    /// argued about in hexadecimal is written once and read wherever a colour
    /// is needed.
    func ink(in scheme: ColorScheme) -> Ink {
        scheme == .dark ? dark : light
    }

    /// The colour a view paints with.
    func color(in scheme: ColorScheme) -> Color {
        ink(in: scheme).color
    }

    /// On paper : dark enough to be read at a caption size, and pulled back
    /// from the saturation a screen offers, since eight loud hues on one page
    /// is a page nobody can look away from.
    private var light: Ink {
        switch self {
        case .publicLife: Ink(0x1D6CA8)
        case .money: Ink(0x0C736C)
        case .land: Ink(0x477219)
        case .body: Ink(0xC22F2C)
        case .everyday: Ink(0x9E5512)
        case .science: Ink(0x5B54C0)
        case .culture: Ink(0xAC3A7A)
        case .plain: Ink(0x6C6C70)
        }
    }

    /// At night : the same eight hues lifted rather than restated, since a
    /// colour picked for white paper reads as ink on a dark ground and a
    /// colour picked twice is two colours the day one of them is changed.
    private var dark: Ink {
        switch self {
        case .publicLife: Ink(0x6FB2FF)
        case .money: Ink(0x4FC7BA)
        case .land: Ink(0xA3C558)
        case .body: Ink(0xFF7A72)
        case .everyday: Ink(0xE8973F)
        case .science: Ink(0xA79FFF)
        case .culture: Ink(0xEC85BC)
        case .plain: Ink(0x9C9CA1)
        }
    }
}
