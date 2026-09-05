//
//  MarkRow.swift
//  Flong
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Several publishers, by their marks rather than by a count of them.
///
/// `4 rédactions` is a number a reader has to turn back into rooms. Four marks
/// are the rooms, and they say which ones, which is the question behind the
/// number : a story every paper is running and a story only the trade press is
/// running are not the same story. An author's row and a newsmaker's ask the
/// same question about a person rather than about a story, and answer it the
/// same way.
///
/// **One drawing, and it was four.** The row of a front page, the head of a
/// story's own page, an author's row and a newsmaker's each set the same marks
/// out by hand, at their own sizes and spacings, and only one of the four kept
/// its count on a line. The comment over the second said `the same marks the
/// row carried`, which was the intention and not the fact : a fault fixed in
/// one was a fault left in the other three. There is one of it now, and what a
/// caller chooses is how large it is drawn and whether there is a count.
///
/// **And nothing is said to VoiceOver here.** A row of marks means a different
/// thing in each of the four places it is drawn : the rooms running a story,
/// the papers somebody writes for, the papers writing about somebody. The
/// drawing is the same and the sentence is not, so the sentence stays where the
/// row is.
struct MarkRow: View {
    /// The publishers whose mark is shown, by the domain each is known by, in
    /// the order the page ranks them.
    let domains: [String]

    /// How many there are in all, where what is drawn is a sample of a larger
    /// number and says so with a `+`. Nothing where the row is all there is,
    /// which is what an author's row wants : four marks are a hint of where
    /// somebody writes rather than an inventory of it, and the row already
    /// carries a number of its own.
    var total: Int?

    /// How wide one mark is drawn. A row of the front page can spare a little
    /// less than the head of a story's own page.
    var side: CGFloat = 14

    /// How far one mark laps the next.
    ///
    /// A quarter of a disc. Enough that the row reads as one group and gives
    /// back the space that separate marks were spending on gaps ; little enough
    /// that every mark still shows the side that says which publisher it is,
    /// since a favicon is recognized by its shape and its colour and both live
    /// at its edge as much as at its middle.
    ///
    /// Taken from the width rather than stated, so the lap is the same share of
    /// a mark at every size it is drawn at.
    private var overlap: CGFloat { side / 4 }

    /// How much wider than the mark in front the bite is cut.
    ///
    /// A hairline of the page, which is all a cut needs to read as one shape in
    /// front of another. Wider and the row is a set of crescents.
    private static let cut: CGFloat = 1

    var body: some View {
        HStack(spacing: -overlap) {
            // **They lap, and the first one is in front.** A row read left to
            // right is a row whose first thing is on top. `zIndex` is what says
            // so, since a stack draws in the order it is written and that order
            // is the opposite one.
            ForEach(Array(domains.enumerated()), id: \.element) { position, domain in
                // **The one in front cuts the one behind.** Two favicons
                // meeting under a hairline read as one shape with a seam, and
                // several of the marks a French reader follows are black discs.
                // The obvious answer is a shadow, and it is only half an answer:
                // a shadow separates by darkening what is behind it, so on a
                // dark page, where the disc behind is already black, it does
                // nothing at all. The answer after that is a light halo on dark
                // pages, and that is a sticker.
                //
                // What the row wants is a hole. Every mark but the first is
                // masked by its own shape less the shape of the one lapping it,
                // grown by a hair, so the gap between two discs is the page
                // itself and it is the page whatever colour the page is. There
                // is nothing to tune for an appearance and nothing to draw.
                SourceStamp(domain: domain, side: side, showsName: false)
                    .mask { cutout(behind: position > 0) }
                    .zIndex(Double(domains.count - position))
            }

            if let total, total > domains.count {
                // **It may not be squeezed, and `lineLimit` does not say
                // that.** A line limit caps how many lines a text may take and
                // says nothing about the width it is given : on the front page
                // this sits at the end of a row already being compressed to fit
                // beside a picture, and offered less width than `+4` needs it
                // broke between the sign and the figure. Two lines for two
                // characters, reading as a stray `4` under a stray `+`.
                Text(verbatim: "+\(total - domains.count)")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // The lap is negative space the whole row carries, and this
                    // is not one of the marks : it takes the lap back and the
                    // gap it had, or the count sits on the last disc.
                    .padding(.leading, overlap + 3)
            }
        }
    }

    /// One mark, less the bite the mark in front of it takes out of it.
    ///
    /// The first of the row is whole, having nothing in front of it.
    private func cutout(behind: Bool) -> some View {
        Rectangle()
            .overlay {
                if behind {
                    Circle()
                        .frame(width: side + Self.cut * 2, height: side + Self.cut * 2)
                        .offset(x: -(side - overlap))
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }
}
