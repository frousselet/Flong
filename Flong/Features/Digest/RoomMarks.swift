//
//  RoomMarks.swift
//  Flong
//
//  Created by François Rousselet on 05/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Who is running a story, by their marks rather than by a count of them.
///
/// `4 rédactions` is a number a reader has to turn back into rooms. Four marks
/// are the rooms, and they say which ones, which is the question behind the
/// number : a story every paper is running and a story only the trade press is
/// running are not the same story.
///
/// **One drawing, and it was two.** The row of a front page and the head of a
/// story's own page each set the same marks out by hand, at two sizes, with two
/// spacings and one of the two lacking the line limit on its count. The comment
/// over the second said `the same marks the row carried`, which was the
/// intention and not the fact : a fault fixed in one was a fault left in the
/// other, and that is exactly what happened. There is one of it now, and what a
/// caller chooses is how large it is drawn.
///
/// The count survives for anyone listening to the page rather than looking at
/// it, and for the rooms there was no room to show.
struct RoomMarks: View {
    /// The rooms whose mark is shown, in the order the page ranks them.
    let marks: [FeedMark]
    /// How many rooms there are in total, which is what the `+` stands for and
    /// what a reader listening to the page is told.
    let count: Int
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
            ForEach(Array(marks.enumerated()), id: \.element.id) { position, mark in
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
                SourceStamp(domain: mark.room, side: side, showsName: false)
                    .mask { cutout(behind: position > 0) }
                    .zIndex(Double(marks.count - position))
            }

            if count > marks.count {
                // **It may not be squeezed, and `lineLimit` does not say
                // that.** A line limit caps how many lines a text may take and
                // says nothing about the width it is given : on the front page
                // this sits at the end of a row already being compressed to fit
                // beside a picture, and offered less width than `+4` needs it
                // broke between the sign and the figure. Two lines for two
                // characters, reading as a stray `4` under a stray `+`.
                Text(verbatim: "+\(count - marks.count)")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // The lap is negative space the whole row carries, and this
                    // is not one of the marks : it takes the lap back and the
                    // gap it had, or the count sits on the last disc.
                    .padding(.leading, overlap + 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(count) rooms"))
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
