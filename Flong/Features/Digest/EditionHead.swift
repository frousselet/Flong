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

    /// The few things worth knowing, on the pane the page opens with.
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
    /// edition stopped and the news began. The pane says it in one move.
    ///
    /// **One pane and not three.** A card per point was the other way, and
    /// three panes of glass with three shadows at the head of a page is three
    /// objects where there is one thing being said. What tells the points apart
    /// inside it is the order the model already wrote them in : see
    /// ``EditionPoints``.
    ///
    /// An edition with no points is not drawn at all : the pane would be an
    /// empty sheet of glass at the head of a page.
    @ViewBuilder
    var body: some View {
        if !published.edition.points.isEmpty {
            EditionPoints(published: published)
                .editionPane()
                .padding(.vertical, Editorial.rhythm)
        }
    }
}

/// What an edition says, ranked, wherever it is drawn.
///
/// **One drawing and it was three.** The same three sentences were set out by
/// hand at the head of the front page, again at the head of a back number and
/// again in the row that opens one, with two mark weights, two column gaps,
/// three spacings between them, and only one of the three ranking the points.
/// What told them apart was where they were drawn, which is the one thing that
/// ought not to change what they say : a reader who opened yesterday's edition
/// from the calendar met a plainer copy of this morning and nothing on the page
/// explained why. There is one of it now, and what a caller chooses is how many
/// points to show and what ground to lay them on.
///
/// **Three points of one weight, and it is the whole of what the list means.**
/// They were set at one size, one weight and one colour, and for a while they
/// were not : the first was given the theme's display face and the two under it
/// stood back, on the argument that the model is asked for what matters in the
/// order it matters. The premise was wrong. The three points are three things
/// worth knowing and they are worth knowing equally ; nothing scores them,
/// nothing checks the order they come back in, and a page that set one of them
/// larger would be inventing a hierarchy and then asking the reader to believe
/// it. Emphasis has to be earned somewhere, and there is nowhere here it could
/// be.
///
/// **They are prose, so they are set in prose's face.** Not `.font(.body)`,
/// which was the only block of type on the front page that asked nobody : under
/// `Papier` and `Solarized` every headline and caption changed face and the
/// pane did not. Through ``Theme/standfirst(_:)`` it asks, and the answer is
/// the same sans in all three themes, for the reason that token gives : a theme
/// speaks in the line that is glanced at, and prose is not glanced at.
///
/// **And nothing is truncated.** There is no line limit here nor anywhere else
/// a point is drawn. What holds a point to a readable length is the model, and
/// it is held in words : see ``EditionSummarizer/maximumPointWords``.
struct EditionPoints: View {
    let published: PublishedEdition

    /// How many points are shown.
    ///
    /// The whole list at the head of an edition ; the first two in a row of the
    /// archive, where the section over the row already says which edition it is
    /// and the whole list would be one back number to a screenful.
    var showing = EditionSummarizer.mostPoints

    @Environment(\.theme) private var theme

    /// The air between one point and the next, at the size the reader reads at.
    ///
    /// **The rhythm is a ratio, and it was two fixed numbers.** Six points of
    /// leading inside a point against eighteen between two of them is the whole
    /// of what tells three points apart, since the rule that used to do it was
    /// deleted and nothing replaced it. Both were held at the size they were
    /// written at while the type they space is not : at the accessibility sizes
    /// a line stands three times as tall, the twelve points that separated two
    /// points from two lines of one had stopped separating anything, and the
    /// list read as one block of prose. That is worst exactly where it matters
    /// most, since a reader at those sizes has fewer words on the screen and
    /// more to hold on to.
    ///
    /// Read through the reader's own type the ratio holds at every size, and at
    /// the ordinary one every number is what it was : nothing a reader at the
    /// default size can see has moved. The environment is read when they change
    /// their type and never on a frame of anything, which is what
    /// ``EditionSinking`` already does with the travel and what
    /// ``EditionPlaceholder`` already does with its bars.
    @ScaledMetric(wrappedValue: EditionHead.pointAir, relativeTo: .body)
    private var pointAir: CGFloat

    /// The air a point carries between its own lines, scaled with the gap
    /// between two of them and for the same reason : what the reader reads is
    /// not either number but the ratio, and a ratio kept at one size and lost at
    /// every other is a ratio nobody decided.
    @ScaledMetric(wrappedValue: EditionHead.leading, relativeTo: .body)
    private var leading: CGFloat

    /// What this edition says, and never more than the bound.
    ///
    /// Read here as well as written : an edition published before the bound
    /// came down carries five points, and every page that draws one has the
    /// same rule about how many it shows.
    private var said: [String] {
        Array(published.edition.points.prefix(min(showing, EditionSummarizer.mostPoints)))
    }

    /// The mark one point wears, or the tag where nothing was matched.
    ///
    /// A point about a story the filing never reached is an ordinary state
    /// rather than a fault : half a mark on a row of marks reads worse than a
    /// neutral one.
    private func mark(at index: Int) -> String {
        guard index < published.marks.count else { return Topic.defaultSymbol }
        return published.marks[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: pointAir) {
            ForEach(Array(said.enumerated()), id: \.offset) { index, point in
                line(point, wearing: mark(at: index))
            }
        }
        .lineSpacing(leading)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One thing said once, rather than three sentences and three glyphs
        // read out as six things. The marks are inside a run of text and are
        // hidden from VoiceOver by being images in it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Written by the model : \(said.joined(separator: ". "))"))
    }

    /// One point, behind the mark of the subject it is about.
    ///
    /// **The subject's own mark, and it was a rule.** A rule is what a page uses
    /// where there is nothing to say about an item beyond that it is one of
    /// several ; here there is, since a point is about a story and a story is
    /// filed under a subject, so the line says what kind of news it is before it
    /// is read.
    ///
    /// **Set into the line, and it stood beside it.** The mark had a column of
    /// its own, twenty points wide with twelve of air after it, and every
    /// wrapped line of a point came back to the far side of it. That is what
    /// ``StorySummary`` argues against one file away : a label pinned next to a
    /// paragraph holds a gutter open down the whole pane, it takes the width
    /// away from the words at the one size where they have least to spare, and a
    /// point of three lines indented past a glyph reads as a quotation. It
    /// matters more now than it did, since a point that used to stop at three
    /// lines may run further.
    ///
    /// **One `Text` and not two views.** A glyph that is part of a sentence has
    /// to break with the sentence, and only a single run of text does that.
    ///
    /// **And it takes the colour of the line it stands in front of.**
    /// ``StorySummary`` sets its own mark quieter than the words, because that
    /// mark is an attribution : it says who wrote the sentence and is not part
    /// of it. This one says what kind of news the sentence is, which is as much
    /// a part of the line as the words are, and one set quieter than them reads
    /// as furniture. So it inherits, and is told apart by its size alone.
    ///
    /// **A symbol is not a letter.** Set at the font of its line it fills the
    /// cap height and comes out heavier than anything beside it, so the mark
    /// takes a step down from what the line is set at : read before the
    /// sentence, never instead of it. A step of the scale and not a size in
    /// points, so it grows with the reader's type.
    ///
    /// **And the step down is smaller than it was, which is what it was always
    /// meant to be.** The mark is set semibold so that a glyph reads as a mark,
    /// and against words at the face's own regular grade that came out as a
    /// jump : the paragraph above asks for a mark read *before* the sentence and
    /// it was being read *instead* of it. The words carry a grade now, the two
    /// stand one step apart rather than two, and nothing about the mark changed
    /// to get there.
    private func line(_ point: String, wearing symbol: String) -> some View {
        let badge = Text(Image(systemName: symbol))
            .font(.system(.footnote, weight: .semibold))

        return Text(
            "\(badge) \(Text(verbatim: point))",
            comment: "A line the model wrote, behind the mark that stands in front of it"
        )
        .font(theme.standfirst(.body).weight(EditionHead.pointGrade))
        .foregroundStyle(.primary)
        // **What makes `never cut` true rather than merely intended.** A row of
        // a `List` clips what it was not told to make room for, and one of the
        // places this is drawn is a row of a `List`.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension EditionHead {
    /// How much air a point carries between its own lines, at the reader's
    /// ordinary type size.
    ///
    /// Set against the air between two points, which is three times it : two
    /// points set as openly as the lines inside one are two points a reader
    /// cannot tell apart. Both are read through the reader's own type where they
    /// are used, so the three to one holds at every size and not only at this
    /// one. See ``EditionPoints``.
    static let leading: CGFloat = 6

    /// The air between one point and the next.
    ///
    /// **It was a hairline, and it is air.** The points were told apart by a
    /// `Divider` apiece, set in from the marks, which made this the one place on
    /// the front page where a rule ran *inside* an object : uniform type between
    /// hairlines in a rounded rectangle is the shape of a grouped table of
    /// settings, and the rule that used to sit *under* this pane was deleted for
    /// less, on the ground that a rule between two rows is what separates one
    /// story from the next. What tells three points apart is the air between
    /// them and nothing else, since they are set at one size, one grade and one
    /// colour and nothing here may rank them.
    ///
    /// Which is why it follows the reader's type. Air doing a rule's work has to
    /// hold at every size the rule would have held at.
    static let pointAir: CGFloat = 18

    /// The grade the three points are set in.
    ///
    /// **It belongs to the block and never to a line.** Nothing here ranks the
    /// points and nothing may : they are three things worth knowing equally,
    /// nothing scores them and nothing checks the order they come back in. A
    /// grade carried by all three at once is not a ranking, it is what the pane
    /// is set in, the way the measure and the leading are ; the moment it were
    /// carried by one it would be the display face on the first point all over
    /// again. There is one call site, in ``EditionPoints/line(_:wearing:)``, so
    /// there is nowhere for a second answer to appear.
    ///
    /// **And it is what the ground asks for.** Body type at the face's own grade
    /// is set for paper, which is what the ten stories under this are set on.
    /// The pane is not paper : it resolves against a colour a publisher's
    /// photograph gave the page that morning, it frosts for a reader who asked
    /// for less transparency, it goes stark for one who asked for more contrast,
    /// and how dense it is at all is a setting on the reader's own device rather
    /// than a decision this file gets to make. It is the one block of type in
    /// the application whose ground is different every day, and one grade of ink
    /// holds on all of them where anything tuned to how much shows through holds
    /// on one.
    ///
    /// **And a standfirst is set apart from the news it stands in front of.**
    /// The pane exists because three sentences of body type above ten stories of
    /// body type is a wall of grey, and the answer it gave was a container drawn
    /// round the words. A newspaper answers in the setting as well, since the
    /// line saying what is in the paper has never been set the same as the
    /// paper. This is that half of the answer, and it is the half that costs no
    /// material. Medium and not semibold : two grades over two or three
    /// sentences is a heading, and the page is titled with its date already.
    static let pointGrade: Font.Weight = .medium

    /// How far the words stand in from the edge of the pane, on all four sides.
    ///
    /// **One number where there were three.** It was sixteen at the sides, four
    /// at the top and bottom and thirteen more above and below every point, so
    /// the air over the first word came to seventeen by an arithmetic nobody had
    /// written down and which was right only for as long as the row padding
    /// beside it stayed what it was. The rows have no padding of their own now.
    ///
    /// A shade wider than ``pointAir`` : an outer margin narrower than the gap
    /// inside is a block that has slipped off its own paper.
    static let paneInset: CGFloat = 20

    /// The corner of the pane.
    ///
    /// Wide, because the pane holds a paragraph rather than a control : a corner
    /// is read as a share of the shape it cuts, and this one runs the whole
    /// column. Tighter and a shape this size reads as a dialog box, and the
    /// material is at its best on a shape a page could have been cut from.
    static let paneCorner: CGFloat = 28

    /// How far the page scrolls before the pane has gone entirely, at the
    /// reader's ordinary type size.
    ///
    /// **A travel and not a measurement.** It used to claim to be the height of
    /// the pane, which it never quite was and, now that a point runs to as many
    /// lines as it needs, is not close : what it says is how much scrolling it
    /// takes for the head to be finished with. It is scaled with the reader's
    /// type where it is read, since the pane grows with the type and a fixed
    /// travel faded the head out while most of it was still on the screen. See
    /// ``EditionSinking``.
    static let sinking: CGFloat = 200

    /// What share of the scroll the pane is held back by.
    ///
    /// Half, so it drifts up at half the speed of the news going past it, which
    /// is what reads as depth rather than as a view that is stuck.
    static let lag: CGFloat = 0.5

    /// How far the pane shrinks on its way out.
    static let shrink: CGFloat = 0.14
}

extension View {
    /// Lays this on the pane an edition's head stands on.
    ///
    /// **A modifier, so there is one pane and no second place for a number to
    /// drift in.** The front page's head, a back number's head and the skeleton
    /// that stands in for either all ask for the pane in the same words, and a
    /// change to the inset or the corner moves all three by construction. The
    /// skeleton in particular has to have it : drawn as a bare list where the
    /// edition arrives on a pane, it is the wrong height and the wrong shape,
    /// and the page moves twice rather than not at all.
    ///
    /// **And no container round it.** A `GlassEffectContainer` exists to merge
    /// the shadows of several shapes of glass and to hand their tints out by
    /// identity, and there is one shape here : it merged nothing and identified
    /// nothing.
    ///
    /// **And it is not tinted.** The pane sits over the colour the lead
    /// photograph gives the page. A tint is an instruction, an instruction
    /// overrides the material's own adaptation, and what it would override here
    /// is a hue nobody chose.
    ///
    /// **And nothing is drawn on its edge.** A rim is the obvious way to make
    /// the pane read more firmly where there is no wash behind it, and it is the
    /// one thing that must not be added : the system already draws a contrasting
    /// border round this material for a reader who asked for more contrast. A
    /// line of our own is that line twice, for the readers least able to absorb
    /// two. What may be laid on this material is a fill, a transparency or a
    /// vibrancy, and nothing else : a second material on it is glass on glass.
    ///
    /// **And it is looked at where its own argument has been switched off.** Two
    /// readers never see what this pane was designed against. Under Reduce
    /// Transparency the material frosts and what is behind it stops showing
    /// through, which is half the case for a pane here ; under Increase Contrast
    /// it goes near black or near white behind a border of the system's drawing,
    /// and ``PageWash`` lays down no colour at all, so the pane stands on plain
    /// paper with nothing behind it. Neither is answered in code, deliberately :
    /// the material already does the right thing to itself, and a branch of our
    /// own would be this file second-guessing a setting the reader chose, which
    /// is the argument ``Theme/paints`` already makes about the standard theme.
    /// What carries the pane there is its inset and the grade its words are set
    /// in, which is what a back number already relies on.
    func editionPane() -> some View {
        padding(EditionHead.paneInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: EditionHead.paneCorner))
    }
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

    /// **The travel follows the reader's type, because the pane does.** It was
    /// a constant, about the height of an ordinary pane at the ordinary size. A
    /// point is no longer held to three lines, so at the larger sizes the pane
    /// is two and three times that tall and a fixed travel faded it out while
    /// most of it was still on the screen. A scaled metric is read from the
    /// environment when the reader changes their type and never per frame, so
    /// this costs the parallax nothing it was not already paying.
    @ScaledMetric(wrappedValue: EditionHead.sinking, relativeTo: .body)
    private var sinking: CGFloat

    /// **A parallax is the motion a reader who asked for less of it meant.**
    /// The fade stays, since what it says is that the head is behind the news
    /// now, which is information ; the drift and the shrink are the movement
    /// itself, and they stop. It is what the live dot does under the same
    /// setting, and the skeleton's band of light, and the charts.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        // Never below nought : a page pulled past its own top is a page being
        // refreshed, and the head has no business moving for that.
        let travelled = max(offset.scrolled, 0)
        let gone = min(travelled / sinking, 1)
        // **It holds, and then it goes.** The fade and the shrink ran straight
        // off the distance travelled, so the pane was at half its ink after a
        // hundred points of scroll, which is while it is still the thing the
        // reader is looking at : something that begins to leave the instant the
        // page is touched reads as something that was never quite there. Eased,
        // it barely moves through the first third and is gone through the last,
        // which is what the parallax was already claiming about it. The drift
        // is not eased with them : it is the reader's own finger, and a
        // parallax that ran ahead of the scroll it is held back against would
        // be a pane sliding on its own.
        let leaving = gone * gone * (3 - 2 * gone)

        // **Drawn only while it is there.** Once it has gone entirely the pane
        // was still a pane : a shape of glass, faded to nothing, sampling what
        // is behind it on every frame of the rest of the scroll, for a reader
        // who cannot see it. And it is held back against the scroll, which is
        // exactly what keeps it near the screen instead of letting the stack
        // leave it behind. `hidden` keeps the room it takes and stops the
        // drawing, so nothing moves and nothing is composited.
        //
        // **And nothing rasterized over it.** Drawing the pane once and moving
        // the picture of it is the right answer for something painted and the
        // wrong one for the material : a bitmap is a snapshot, and what the
        // material draws is whatever is behind it at this moment.
        //
        // **And it is not blurred.** A blur over the material is two passes off
        // screen for every frame of the first two hundred points of every
        // scroll, which is the one stretch of page a reader crosses every
        // morning. What defended it was a doc comment saying the pane was a
        // fill, and it has not been a fill for some time. The easing says what
        // the blur was there to say and costs nothing.
        //
        // A simulator draws glass cheaply and shows none of this ; a device
        // draws the real thing.
        if gone >= 1 {
            content.hidden()
        } else if reduceMotion {
            content.opacity(1 - leaving)
        } else {
            content
                // Held back against the scroll, so it falls behind the page
                // rather than travelling with it.
                .offset(y: travelled * EditionHead.lag)
                .scaleEffect(1 - leaving * EditionHead.shrink, anchor: .top)
                .opacity(1 - leaving)
        }
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
    /// What the bars are drawn in.
    ///
    /// **A rung up for the ones drawn on glass.** The lightest fill there is
    /// reads as an absence on paper, which is what a skeleton is for, and the
    /// same fill on the material came back at pure white : `interface.md` has
    /// the measurement, taken over the arrivals strip, and not one pixel of a
    /// bar differed from the paper it stood on. The bars inside an edition's
    /// pane are the only ones in the application laid on the material rather
    /// than on paper, and a skeleton nobody can see is the one thing the pane
    /// must never be, an empty sheet of glass at the head of a page.
    var fill: HierarchicalShapeStyle = .quaternary

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
        let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(fill)

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
    /// The bar that stands for a line of a point, and the air after it.
    ///
    /// **A bar and its air stand for a line of type and its leading.** A point
    /// is set at the body step, where a line and the six points of leading
    /// under it come to twenty-eight. Thin next to the space around it, because
    /// what a skeleton is is thin, even rules light enough to read as an
    /// absence rather than as content.
    ///
    /// **One height for all three, because the pane sets all three alike.** The
    /// skeleton ranked them for a while, a taller bar for the first, and it was
    /// promising a hierarchy the page does not draw : three points are three
    /// things worth knowing equally.
    ///
    /// **Scaled, because the type it stands for is.** Held at the size it is
    /// drawn at today, the skeleton was the right height for a reader at the
    /// default size and the wrong one for everybody else, and the page moved by
    /// the difference for all of them when the words landed, which is the whole
    /// of what this exists to stop.
    @ScaledMetric(relativeTo: .body) private var bar: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var air: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: EditionHead.pointAir) {
            // **Keyed by where it stands and not by what it holds.** These are
            // three points of two, one and two lines, and `id: \.self` over
            // that is the identity 2 twice : SwiftUI says so at runtime and
            // then gives undefined results, which for a placeholder means a bar
            // that flickers or does not animate out with its neighbours.
            ForEach(Array(Self.points.enumerated()), id: \.offset) { _, lines in
                TextPlaceholder(
                    lines: lines, last: lines > 1 ? 0.5 : 0.8, height: bar, spacing: air, fill: .tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **The same pane, asked for by name.** The skeleton exists to hold the
        // room the thing it stands for will take, so it takes the pane the way
        // the head takes it and there is no way for the two to drift : the same
        // inset, the same corner, the same air between points, and the same
        // rhythm above and below, which is what the page moved by when the
        // words landed for as long as the head had a rhythm over it and this
        // had none.
        .editionPane()
        .padding(.vertical, Editorial.rhythm)
        // What tells a page that is filling in from a page that is broken. The
        // real pane never does this.
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
    ///
    /// **And it settles by growing and never by shrinking.** A bar and the air
    /// after it come to a line of type and its leading, and the last line of a
    /// block has no air after it, so a block stands one leading short of the
    /// type it replaces. That is about a dozen points across the three of them,
    /// under the height of one word, and it is all in the same direction : the
    /// page grows into its edition rather than shrinking onto it.
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
