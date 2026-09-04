//
//  Editorial.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The few decisions that make the interface look like one thing.
///
/// Everything here is a token rather than a value typed at a call site : one
/// place to change a measure or a rhythm, which is how a design stays
/// consistent while it is still being argued about.
///
/// **The faces moved to ``Theme``.** They were three tokens here and they were
/// the right three ; what changed is that there is more than one answer to each
/// of them. A headline is serif, or sans, or monospace, depending on which
/// theme the reader chose, and a static property has nowhere to read that from.
/// The measures stayed : a column is 680 points wide in every theme, since the
/// eye loses a long line whatever face it is set in.
nonisolated enum Editorial {
    /// The width a column of text may reach.
    ///
    /// Around seventy characters at the body size. Wider is measurably harder to
    /// read, and a window three times this wide should hold one column of text
    /// and a great deal of quiet, not three columns of text.
    static let measure: CGFloat = 680

    /// The vertical rhythm between stories.
    /// The shape every picture is shown in, lead and thumbnail alike.
    ///
    /// Three by two, which is what a camera takes and therefore what a
    /// publisher's picture already is : any other ratio is a crop, and a crop
    /// is a decision about somebody else's photograph.
    ///
    /// One ratio for the whole page rather than a band above and squares
    /// beside : a column whose pictures are all the same shape has a rhythm,
    /// and one whose pictures each have their own does not.
    static let pictureAspect: CGFloat = 3.0 / 2.0

    static let rhythm: CGFloat = 28
    static let tightRhythm: CGFloat = 10
}

nonisolated extension View {
    /// Holds a view to the measure, centred, whatever the window does.
    func editorialColumn() -> some View {
        frame(maxWidth: Editorial.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A dot that says something is still arriving.
///
/// The motion is the information : a story nobody is adding to has a still dot,
/// and one that is moving has a moving dot. It stops entirely when the reader
/// has asked for less motion.
struct LiveDot: View {
    /// How faint the dot goes at the bottom of its pulse.
    ///
    /// A heading beside it takes this rather than the full colour : the dot is
    /// the loud thing and the word is what it means, so the word sits at the
    /// quiet end of the same breath and the pair reads as one mark rather than
    /// as two red things competing.
    static let faded = 0.55

    /// The colour a heading beside the dot is set in.
    ///
    /// Asked for rather than written twice : a heading beside the dot has to be
    /// the dot's own colour, and two literals that happen to agree today are
    /// two literals that stop agreeing the first time one of them is changed.
    static func quietTint(_ theme: Theme) -> Color {
        theme.live.opacity(faded)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(theme.live)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing ? 1.35 : 1)
            .opacity(isPulsing ? Self.faded : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = !reduceMotion }
            .accessibilityHidden(true)
    }
}

/// The shape of a story's arrival.
///
/// It tells a burst from a trickle at a glance, which is the one thing a number
/// cannot say.
///
/// **It scales to itself, and the number beside it is the comparison.** One
/// row's busiest moment is the top of that row. Scaled instead against the
/// busiest source of a whole page, as the figures first drew them, five of six
/// publishers came out as a flat run of hairlines : the shape is there to say
/// whether a week was steady or had a Thursday in it, and a shape flattened to
/// nothing says neither.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(values.max() ?? 1, 1)
            // **The gap gives way before the bar does.** A fixed gap beside a
            // bar clamped to a minimum width is a row that adds up to more than
            // it was given : a hundred and thirteen months of arrivals in sixty
            // points ran clean off the end of its own row and drew a dotted
            // rule across the source beside it. The slot is the width divided,
            // and the gap is a share of the slot, so the sum is the width
            // however many marks there are.
            let slot = geometry.size.width / CGFloat(max(values.count, 1))
            let gap = min(1.5, slot * 0.3)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .frame(
                            width: max(slot - gap, 0.5),
                            height: max(geometry.size.height * CGFloat(value) / CGFloat(peak), 1.5)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
}

/// When a story was last added to, which is the only time it has.
///
/// **A glyph rather than the words.** The line under a story is the one place
/// on the front page where everything is abbreviated already : the rooms are
/// marks rather than names and the arrivals are a sparkline rather than a
/// count, and `mis à jour il y a 21 minutes` in the middle of that is a
/// sentence in a row of shorthand. The mark is the one an article's own page
/// wears for a revision, `clock` turned back on itself, so a reader who has
/// opened one article knows what it means here : see `ArticleDocument.Moment`.
///
/// **And it stays relative, where an article's moment became absolute.** What
/// a front page says about a story is how fresh it is, and `il y a 3 minutes`
/// is exactly that ; an article is a thing with a date, and the date is what a
/// reader wants of it. See ``ArticleMoment``.
struct StoryMoment: View {
    let date: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.circlepath")
            Text(date, format: .relative(presentation: .numeric))
        }
        .lineLimit(1)
        // A shape says nothing to a reader who is not looking at it, and a
        // time on its own says nothing about what happened then.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Updated \(date, format: .relative(presentation: .named))"))
    }
}

/// When an article happened, said as precisely as what is known allows.
///
/// **Three different things wear the same shape, and saying so is the point.**
///
/// - **Published.** What a feed states. It is what the page sorts by, so it is
///   what the row leads with : a list ordered by one date and labelled with
///   another is a list that looks wrongly sorted, and the reader is right.
/// - **Received.** Some feeds date nothing at all : `Le Parisien` states a
///   build date for the channel and none for any of its items, so a hundred of
///   its articles have only the moment they were pulled to sort by. That is the
///   honest answer and there is no other, but it must not be shown as though
///   the publisher had said it. A row reading `il y a deux heures` about an
///   article nobody dated is telling the reader something nobody knows.
/// - **Updated.** A publisher who went back to the piece after publishing it.
///   It is said after the publication and never instead of it : **it changes
///   nothing about where the article sits**, and a row that led with it would
///   say so falsely. Only where the publisher states one and it is more than a
///   minute later, since stamping both at the same second is publishing rather
///   than updating.
///
/// The update's own time is dropped before the fact of it is, since a row has
/// one line and knowing that a piece was revised matters more than knowing to
/// the minute when. The article's own page has room for both.
///
/// **The moment is written out and no longer counted back from now.** It read
/// `il y a 2 heures`, which is one thing a reader wants to know and a poor way
/// to be told it : a list of a morning's articles came out as twenty
/// phrasings of the same hour, none of them comparable at a glance, all of
/// them going stale while the page sat open. Two articles an hour apart are
/// `9:05` and `10:12`, and the reader does the subtraction they were going to
/// do anyway. A story is the other case and keeps its relative time : what a
/// front page says about a story is how fresh it is, and `il y a 3 minutes` is
/// exactly that.
///
/// The day and the month with it, and the year only where it is not this one :
/// a stamp reading `11:15` is unreadable in a list that reaches back three
/// days, and one carrying `2026` on every line of today's news is a column of
/// noise.
struct ArticleMoment: View {
    let date: Date
    /// Whether that moment is the publisher's own, or only when the piece
    /// reached whoever is showing it.
    var isDated = true
    var updatedAt: Date?

    init(article: ArticleSummary) {
        date = article.date
        isDated = article.isDated
        updatedAt = article.updatedAt
    }

    /// The same line for an excerpt somebody shared, which carries a
    /// publication date where its feed stated one and the moment it arrived
    /// where nobody did.
    init(sent entry: SharedEntry) {
        date = entry.date
        isDated = entry.publishedAt != nil
        updatedAt = nil
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(sayingWhen: true)
            line(sayingWhen: false)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func line(sayingWhen: Bool) -> some View {
        HStack(spacing: 4) {
            published

            if let updated = updatedAt {
                Text(verbatim: "·")
                if sayingWhen {
                    Text("updated on \(updated, format: Self.stamp(updated))")
                } else {
                    Text("updated")
                }
            }
        }
    }

    @ViewBuilder
    private var published: some View {
        if isDated {
            Text(date, format: Self.stamp(date))
        } else {
            Text("Received on \(date, format: Self.stamp(date))")
        }
    }

    /// Whole sentences rather than pieces joined end to end : a language that
    /// wants the second date first, or a different stop between the two, has
    /// nowhere to say so when the joining is done here.
    private var spoken: Text {
        guard let updated = updatedAt else {
            return isDated
                ? Text("Published on \(date, format: Self.spelled)")
                : Text("Received on \(date, format: Self.spelled)")
        }

        return isDated
            ? Text("Published on \(date, format: Self.spelled). Updated on \(updated, format: Self.spelled)")
            : Text("Received on \(date, format: Self.spelled). Updated on \(updated, format: Self.spelled)")
    }

    /// How a moment is written in a row : the day, the month and the hour, with
    /// the year only where it is not this one.
    ///
    /// A style built for the moment it is about rather than one constant, since
    /// what a row shows depends on which year the article is from, and a stamp
    /// that carried `2026` on every line of today's news would be a column of
    /// noise.
    static func stamp(_ date: Date, now: Date = .now) -> Date.FormatStyle {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()
        return Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? style : style.year()
    }

    /// The same moment for anyone listening rather than looking, spelled out.
    ///
    /// A row is glanced at and abbreviates ; a sentence read aloud has no such
    /// pressure, and `sam. 1 sept.` is a worse thing to hear than the day said
    /// in full.
    static let spelled = Date.FormatStyle.dateTime
        .weekday(.wide).day().month(.wide).year().hour().minute()
}
