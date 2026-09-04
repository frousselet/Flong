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

    /// How much air a point carries between its own lines.
    ///
    /// Set against the space between points, which is a little wider still :
    /// two points set as openly as the lines inside one are two points a reader
    /// cannot tell apart.
    static let leading: CGFloat = 6

    /// How wide the mark in front of a point is drawn.
    ///
    /// A frame rather than the glyph's own width, so every line of type starts
    /// at the same place whatever its mark is, and so the skeleton can hold the
    /// same room before there is a mark at all.
    static let markWidth: CGFloat = 20

    /// What this edition says, and never more than the bound.
    ///
    /// Read here as well as written : an edition published before the bound
    /// came down carries five points, and the page it is drawn on has one
    /// rule about how many it shows.
    private var said: [String] {
        Array(edition.points.prefix(EditionSummarizer.mostPoints))
    }

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
    /// **And the list stands on a pane of its own.** Set straight on the page
    /// it was three sentences of body type above ten stories of body type,
    /// separated from the news by a hairline and by nothing else : a reader
    /// coming to the page met a wall of grey and had to work out where the
    /// edition stopped and the news began. The pane says it in one move. It is
    /// the third place in the application that draws its own glass, and it
    /// earns it the way the credit on a photograph does rather than the way a
    /// control does : it is not floating over the page to be pressed, it is the
    /// edition's own voice laid on the page, and what is under it goes on
    /// showing through. See `docs/technical/interface.md`.
    ///
    /// **One pane and not three.** A card per point was the other way, and
    /// three panes of glass with three shadows at the head of a page is three
    /// objects where there is one thing being said. The points are told apart
    /// inside it by a hairline, which is the vocabulary the rest of the page
    /// already uses between rows.
    private var points: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(said.enumerated()), id: \.offset) { index, point in
                    if index > 0 {
                        // Set in from the marks, so the rule runs under the
                        // words and not under the column of glyphs : a rule
                        // across the whole pane cuts it into boxes, and this
                        // is one pane with three things on it.
                        Divider()
                            .padding(.leading, Self.markWidth + Self.columnGap)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: Self.columnGap) {
                        // **The subject's own mark, and it was a rule.** A rule
                        // is what a page uses where there is nothing to say
                        // about an item beyond that it is one of several ; here
                        // there is, since a point is about a story and a story
                        // is filed under a subject. The row says what kind of
                        // news each line is before the line is read.
                        //
                        // The page's own colour, like the line beside it. A
                        // mark set quieter than the words it stands in front of
                        // reads as furniture ; this one says what kind of news
                        // the line is, which is as much a part of the line as
                        // the sentence.
                        Image(systemName: mark(at: index))
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: Self.markWidth)
                            .accessibilityHidden(true)

                        // **Three lines, and never a truncated one.** The bound
                        // is kept where the words are written rather than where
                        // they are drawn : the model is held to a hundred and
                        // twenty characters a point, which is under what three
                        // lines hold here, so nothing reaches this and needs
                        // cutting. Setting a long point smaller until it fitted
                        // was the other way, and it is a page whispering the
                        // news. See ``EditionSummarizer/maximumPointCharacters``.
                        Text(verbatim: point)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Self.rowAir)
                }
            }
            // The page's own colour, at the size the rest of the page reads in.
            .font(.body)
            .lineSpacing(Self.leading)
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.paneInset)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.paneCorner))
        }
        // Room between what the edition says and the first story it leads on.
        // They are two different things and were a few points apart.
        .padding(.bottom, Editorial.rhythm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Written by the model : \(said.joined(separator: ". "))"))
    }

    /// How far the page scrolls before the pane has gone entirely.
    ///
    /// About the height of the pane itself : it is finished by the time the
    /// first headline has reached where it stood.
    static let sinking: CGFloat = 200

    /// What share of the scroll the pane is held back by.
    ///
    /// Half, so it drifts up at half the speed of the news going past it,
    /// which is what reads as depth rather than as a view that is stuck.
    static let lag: CGFloat = 0.5

    /// How far the pane shrinks on its way out.
    static let shrink: CGFloat = 0.14

    /// How far out of focus it goes on its way out.
    static let softening: CGFloat = 6

    /// The gap between a mark and the words it stands in front of.
    static let columnGap: CGFloat = 12

    /// The air above and below one point inside the pane.
    static let rowAir: CGFloat = 13

    /// How far the words stand in from the edge of the pane.
    static let paneInset: CGFloat = 16

    /// The corner of the pane.
    ///
    /// Wide, because the pane holds a paragraph rather than a control : a tight
    /// corner on a shape this size reads as a dialog box, and the material is
    /// at its best on a shape a page could have been cut from.
    static let paneCorner: CGFloat = 28
}

/// What the head of the page does as the page is scrolled.
///
/// **It goes back rather than up.** Every other row leaves by the top edge,
/// which is right for a story : it is one of forty and the next one takes its
/// place. What the edition says is the page's own voice and there is one of it,
/// so it holds its ground against the scroll, shrinks, softens and is gone by
/// the time the first headline reaches where it stood.
///
/// **Read off the page's own offset and not off this view's geometry.** The
/// first version measured the pane's position inside the scroll view, which is
/// not nought at rest but the height of everything above it : the pane was
/// pulled up under the subjects the moment the page opened, before anybody had
/// scrolled anything. ``PageOffset/scrolled`` is nought at rest by
/// construction, which is what this needs and what the wash behind the page
/// already uses.
///
/// A modifier of its own, so what re-reads that offset on every frame of a
/// scroll is this and not the front page : the head it is given is a value it
/// passes through untouched, and the page is never invalidated.
struct EditionSinking: ViewModifier {
    let offset: PageOffset

    func body(content: Content) -> some View {
        // Never below nought : a page pulled past its own top is a page being
        // refreshed, and the head has no business moving for that.
        let travelled = max(offset.scrolled, 0)
        let gone = min(travelled / EditionHead.sinking, 1)

        return
            content
            // Held back against the scroll, so it falls behind the page rather
            // than travelling with it.
            .offset(y: travelled * EditionHead.lag)
            .scaleEffect(1 - gone * EditionHead.shrink, anchor: .top)
            .blur(radius: gone * EditionHead.softening)
            .opacity(1 - gone)
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
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 0) {
                // **Keyed by where it stands and not by what it holds.** These
                // are three points of two, one and two lines, and `id: \.self`
                // over that is the identity 2 twice : SwiftUI says so at
                // runtime and then gives undefined results, which for a
                // placeholder means a bar that flickers or does not animate out
                // with its neighbours.
                ForEach(Array(Self.points.enumerated()), id: \.offset) { index, lines in
                    if index > 0 {
                        Divider()
                            .padding(.leading, EditionHead.markWidth + EditionHead.columnGap)
                    }

                    HStack(alignment: .top, spacing: EditionHead.columnGap) {
                        // The room a mark takes, and no mark : a skeleton
                        // claiming a subject before anything has been filed
                        // under one would be a promise, and the page would
                        // change shape twice.
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 14, height: 14)
                            .frame(width: EditionHead.markWidth)
                            .padding(.top, 3)

                        // The same room a line of the real thing takes : a bar
                        // and the air after it come to the height of a line of
                        // type plus its leading, or the page moves when the
                        // words land.
                        TextPlaceholder(
                            lines: lines, last: lines > 1 ? 0.5 : 0.8, height: 9,
                            spacing: EditionHead.leading + 11
                        )
                    }
                    .padding(.vertical, EditionHead.rowAir)
                }
            }
            // **The same pane, and it has to be.** The skeleton exists to hold
            // the room the thing it stands for will take : drawn as a bare list
            // where the edition arrives on a pane, it is the wrong height and
            // the wrong shape, and the page moves twice rather than not at all
            // - once when the pane appears and once when the words land in it.
            .padding(.horizontal, EditionHead.paneInset)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: EditionHead.paneCorner))
        }
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
    /// **Three points, which is what an edition carries.** A placeholder
    /// claiming the exact shape of an answer nobody has yet is a second guess,
    /// so the middle one stands a single line where the two either side stand
    /// two : the page settles by a line rather than by a block.
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
