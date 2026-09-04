//
//  EditionHead.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What an edition says about itself, over the ten stories on it.
///
/// **The masthead of the page.** A front page that was rebuilt on every fetch
/// had nothing to put here : there was no page, only the newest sixty stories
/// in an order that shifted under the reader. An edition is made at an hour, so
/// it can say what is in it before the reader has read a headline.
///
/// **A list, and nothing over it.** An edition carried a name of its own and
/// every real page showed the same thing : the name was the list said again in
/// fewer words. A front page has never had a name, and the three attempts at
/// one are recorded in `docs/technical/digest.md`.
///
/// **And the dateline is the page's own.** It said which edition this is, over
/// the list, which put a second heading under the date the page is already
/// titled with : two lines saying when, one above the other. It stands under
/// the date now, where a masthead puts it, so the page opens on `Vendredi 4
/// septembre` and `Édition du matin, 07:00` and then goes straight to the news.
/// See ``DigestScreen``.
///
/// **And the way to the back numbers is not here.** It was a line under the
/// list, which put a way *out* of the page in the middle of the page : the
/// reader met it between what this edition says and the first story it leads
/// on. It stands in the corner now, beside the notices, and only in this
/// section. See ``EditionsButton``.
///
/// The points are the model's own, in the reader's own language. An edition
/// with none is not shown at all.
struct EditionHead: View {
    let published: PublishedEdition

    private var edition: Edition { published.edition }

    var body: some View {
        VStack(alignment: .leading, spacing: Editorial.tightRhythm) {
            if !edition.points.isEmpty {
                points
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Editorial.rhythm)
        .padding(.bottom, Editorial.tightRhythm)
    }

    /// How wide the mark in front of a point is drawn.
    ///
    /// A frame rather than the glyph's own width, so every line of type starts
    /// at the same place whatever its mark is, and so the skeleton can hold the
    /// same room before there is a mark at all.
    static let markWidth: CGFloat = 20

    /// The mark one point wears, or the tag where nothing was matched.
    private func mark(at index: Int) -> String {
        guard index < published.marks.count else { return Topic.defaultSymbol }
        return published.marks[index]
    }

    /// The few things worth knowing, one per line.
    ///
    /// **A list and not a paragraph.** Asked for two or three sentences over
    /// ten stories the model wrote one clause per story and joined them with
    /// commas, and the line under the headline ran to seven items and eight
    /// lines of type. A front page has always answered this the same way.
    ///
    /// **No glyph in front of it.** The story rows carry one, and there it says
    /// something : a story's line is the model's or its publisher's, and the
    /// mark is how a reader tells which. Nothing on an edition's head is ever
    /// anybody else's, an edition existing only where the model wrote the whole
    /// of it, so a mark here answers a question nobody can ask. It is still
    /// said, to VoiceOver, where a statement costs no ink.
    ///
    /// The list is set with air around it. Five points at the spacing of a
    /// paragraph is a block, and a block is the thing this replaced.
    private var points: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(edition.points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // **The subject's own mark, and it was a rule.** A rule is
                    // what a page uses where there is nothing to say about an
                    // item beyond that it is one of several ; here there is,
                    // since a point is about a story and a story is filed under
                    // a subject. The row says what kind of news each line is
                    // before the line is read.
                    Image(systemName: mark(at: index))
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.markWidth)
                        .accessibilityHidden(true)
                    Text(verbatim: point)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // **One step up from the body, and the page's own colour.** These are
        // the news : they were set in the size and the grey a standfirst is set
        // in, which is right for a line under a headline and wrong here, where
        // there is no headline above them and they are the first thing the
        // reader reads. The rules stay quiet, being marks and not words.
        .font(.title3)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        // Room between what the edition says and the first story it leads on.
        // They are two different things and were a few points apart.
        .padding(.bottom, Editorial.rhythm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Written by the model : \(edition.points.joined(separator: ". "))"))
    }
}

/// What stands where an edition would, when there is not one.
///
/// **Three absences, and never one word for all three.** A device that cannot
/// run the model will never have an edition and has to be told so plainly ; one
/// whose model is still downloading will have one shortly ; and one whose
/// reader has switched every edition off has asked for this. A page that said
/// `no edition` to all three would be a page working exactly as it should and
/// looking exactly like a page that is broken.
struct NoEdition: View {
    let hasSchedule: Bool
    let openSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No edition yet", systemImage: "newspaper")
        } description: {
            if !hasSchedule {
                Text("You have switched every edition off. The wire still holds everything that arrives.")
            } else if let absence = OnDeviceModel.absence {
                Text(absence)
            } else {
                Text("The next edition is being written. It appears once every headline on it is.")
            }
        } actions: {
            if !hasSchedule {
                Button("Edition times") { openSettings() }
            }
        }
    }
}

/// A block of type, before the words are there.
///
/// **Bars, drawn as bars.** The first version redacted real `Text`, which is
/// the shorthand SwiftUI offers and gives a bar the full height of a line of
/// type : chunky slabs the height of the words, one per point, with a stub
/// under each. What a skeleton is is thin, even rules of varying width, light
/// enough to read as an absence rather than as content. So the shapes are drawn
/// rather than borrowed, which also puts the widths under this file's control
/// instead of the string lengths of a sentence nobody will read.
///
/// The last line of a block is short, because the last line of a paragraph is.
struct TextPlaceholder: View {
    /// How many lines the block stands for.
    var lines = 2
    /// What share of the column the last of them fills.
    var last: CGFloat = 0.55
    /// The bar itself. Thin next to the space around it, which is what makes a
    /// skeleton read as ruled paper rather than as a wall.
    var height: CGFloat = 9
    var spacing: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<max(lines, 1), id: \.self) { line in
                bar(isLast: line == lines - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bar(isLast: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(.quaternary)

        if isLast, lines > 1 {
            shape
                .frame(height: height)
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * last }
        } else {
            shape.frame(height: height)
        }
    }
}

/// The shape of an edition, before there is one.
/// The shape of an edition, before there is one.
///
/// **A page that fills in rather than one that appears.** An edition is not
/// published until the model has written the whole of it, so the front page
/// stood empty for the seconds or minutes that takes and then arrived all at
/// once, pushing everything below it down the screen. A reader who had started
/// reading lost their place to a page they had not asked to change.
///
/// So the page draws what it is about to hold : the dateline is already in the
/// title, and here are the lines it will have. `redacted(reason: .placeholder)`
/// draws them as bars, which is what says these are not words to read yet.
///
/// **Three of them, and not five.** A placeholder claiming the exact shape of
/// an answer nobody has yet is a second guess : the model writes three points
/// as often as five, and a page that settled from five bars to three would jump
/// exactly as far as one that settled from nothing. Three is the fewest a list
/// ever has, so the page only ever grows into it.
struct EditionPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // **Keyed by where it stands and not by what it holds.** These are
            // three points of two, one and two lines, and `id: \.self` over
            // that is the identity 2 twice : SwiftUI says so at runtime and
            // then gives undefined results, which for a placeholder means a bar
            // that flickers or does not animate out with its neighbours. What
            // identifies a bar here is its place in the list, nothing else
            // about it being its own.
            ForEach(Array(Self.points.enumerated()), id: \.offset) { _, lines in
                HStack(alignment: .top, spacing: 10) {
                    // The room a mark takes, and no mark : a skeleton claiming
                    // a subject before anything has been filed under one would
                    // be a promise, and the page would change shape twice.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 14, height: 14)
                        .frame(width: EditionHead.markWidth)
                        .padding(.top, 2)
                    TextPlaceholder(lines: lines, last: lines > 1 ? 0.5 : 0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, Editorial.rhythm)
        // What tells a page that is filling in from a page that is broken.
        .shimmering()
        // One thing said once, rather than a set of bars read out as sentences
        // of nonsense.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The edition is being written"))
    }

    /// How many lines each point stands for.
    ///
    /// **Three points and not five, deliberately.** A placeholder claiming the
    /// exact shape of an answer nobody has yet is a second guess : the model
    /// writes three as often as five, and a page settling from five bars to
    /// three jumps exactly as far as one settling from nothing. Three is the
    /// fewest a list ever has, so the page only ever grows into it.
    private static let points = [2, 1, 2]
}

/// The shape of a story on the page, before there is one.
///
/// **The head is not the whole of the jump.** An edition's ten stories arrive
/// with it, so drawing the shape of the list above them and nothing below
/// would move the same page the same distance a moment later. The lead carries
/// a photograph across the column and the rest keep theirs to a square, so
/// there are two shapes to draw and they are the two that take the room.
///
/// **The picture is drawn as a picture.** A skeleton that leaves it out is a
/// skeleton the wrong height, which is the whole of what this exists to stop.
struct StoryPlaceholder: View {
    var isLead = false

    /// The same width the rows that are not the lead keep their picture to.
    private static let thumbnailWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLead {
                picture
                lines
            } else {
                HStack(alignment: .top, spacing: 14) {
                    lines
                    picture.frame(width: Self.thumbnailWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .shimmering()
        .accessibilityHidden(true)
    }

    /// **The lightest fill there is, and it was the second lightest.** A
    /// photograph's worth of solid grey is the one thing on a skeleton that
    /// stops reading as an absence and starts reading as content : the eye goes
    /// to it and finds nothing there. It is still drawn, since leaving it out
    /// would make the skeleton the wrong height and the page would move by
    /// exactly the height of a photograph, which is what this exists to stop.
    private var picture: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(Editorial.pictureAspect, contentMode: .fit)
    }

    /// The headline, then the line under it, as two blocks with space between :
    /// a skeleton of one run of bars says nothing about what the row is made of.
    private var lines: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextPlaceholder(lines: 2, last: isLead ? 0.62 : 0.7, height: isLead ? 13 : 11)
            TextPlaceholder(lines: isLead ? 2 : 1, last: 0.45, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
