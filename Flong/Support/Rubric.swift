//
//  Rubric.swift
//  Flong
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What a story is filed under, set above its headline.
///
/// A reader scanning a page reads it before the headline, the way a rubric is
/// read before the piece under it : it says what kind of news is coming, in
/// small caps, in a line of type rather than in a stack of labels, since labels
/// there would read as controls.
///
/// **Each subject in its own colour, and the dots between them in neither.** A
/// story under two subjects is under two kinds of news, and printing the pair
/// in one colour would say it is under one. The separator keeps the colour of
/// the line, being punctuation rather than a subject. Where a subject's mark is
/// unknown the plain colour stands, which is what the two sections that sort
/// nothing wear anyway.
///
/// **One drawing, and it was two.** The front page and a story's own page each
/// set this line out by hand, at their own size and kerning ; what a caller
/// chooses is the size, and the rest is the same line in both places.
struct Rubric: View {
    /// The subjects the story is filed under, in the order it was filed.
    let topics: [String]

    /// The mark each subject wears, which is what its colour is read from :
    /// see ``StandardTopics/families``.
    let marks: [String: String]

    /// How large the line is set. A row of the front page takes the smaller of
    /// the two, a story's own page the larger.
    var style: Font.TextStyle = .caption2

    /// How far apart the small caps stand, which follows the size.
    var kerning: CGFloat = 0.5

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(line)
            .font(.system(style, weight: .semibold))
            .kerning(kerning)
            // What the colours are laid over : the punctuation between two
            // subjects, which is not a subject and takes no colour of its own.
            .foregroundStyle(.tertiary)
    }

    /// The line itself : one string, in runs of one colour each.
    ///
    /// **An attributed string rather than a sum of `Text`s.** Adding one `Text`
    /// to another is deprecated as of iOS 26, and a stack of labels would stop
    /// this being a line of type : it would not wrap on the page that lets it
    /// wrap, and it would read as a row of controls on the page that does not.
    ///
    /// Set in capitals here rather than by `textCase`, since the case has to be
    /// part of the string the runs are coloured in.
    private var line: AttributedString {
        topics.enumerated().reduce(into: AttributedString()) { line, subject in
            if subject.offset > 0 { line += AttributedString(" · ") }

            var subjectRun = AttributedString(subject.element.localizedUppercase)
            subjectRun.foregroundColor =
                StandardTopics.family(of: marks[subject.element] ?? Topic.defaultSymbol).color(in: scheme)
            line += subjectRun
        }
    }
}
