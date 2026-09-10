//
//  BackNumbers.swift
//  Flong
//
//  Created by François Rousselet on 10/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Where today's paper ends and the ones before it begin.
///
/// **A reader does not open a drawer to find yesterday's paper : it is under
/// today's.** The back numbers stood behind a calendar in the corner of the
/// digest, which is a control that has to be found, opened, chosen from and
/// closed to get at a page that was already written. They are under the page
/// now, and the way to them is the way a reader already knows.
///
/// What this draws is the seam. It is the one place on the page where the
/// reader leaves the present, so it says so in words, holds the scroll for a
/// moment, and is felt as well as seen.
struct BackNumbersMasthead: View {
    /// How far past the foot of the page the reader is pulling, which is what
    /// draws the seam.
    ///
    /// **This one view is rebuilt on every frame of that pull, and that is the
    /// bargain.** The same one ``EditionSinking`` makes at the other end of the
    /// page : a value that moves per frame invalidates the body it is read in,
    /// so it is read in a body that is two rules and three words rather than in
    /// the page they sit on.
    let pull: FootPull

    /// Whether the archive is open under it.
    let isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A name the scroll can be told to catch on.
    static let anchor = "back-numbers"

    /// How far the seam is dragged behind the page while it is being pulled at.
    ///
    /// **In the spirit of the head of the page, which drifts up at half the
    /// speed of the news going past it.** Here it is the seam that holds its
    /// ground while the reader pulls the page out from under it, and catches up
    /// exactly as the pull completes : what reads as depth is the seam and the
    /// paper moving at two speeds, and what reads as resistance is the seam
    /// arriving last. A line of type is the whole of it. See ``EditionHead/lag``.
    private static let cling: CGFloat = 22

    /// How far the seam has come, from nothing to done.
    ///
    /// It is the reader's own thumb that moves it : nothing here is on a clock.
    /// A page that played an animation at the seam would be the application
    /// performing ; this is the page answering the hand, and it completes at
    /// the moment the pull takes and the tap is felt.
    ///
    /// One once the archive is open. What is under the page is no longer being
    /// revealed, so a seam that went on drawing and undrawing itself as the
    /// reader passed it would be an effect for its own sake, and it would drift
    /// over the dateline of the paper underneath.
    private var drawn: CGFloat {
        guard !reduceMotion, !isOpen else { return 1 }
        return min(pull.pulled / PullForBackNumbers.threshold, 1)
    }

    var body: some View {
        // Read once. It is three views deep and it moves per frame.
        let drawn = self.drawn

        VStack(spacing: 10) {
            // Two rules with the words between them, which is what a masthead
            // does : the page above is over, and the page below is a different
            // day. One rule would read as another story's separator.
            //
            // They open from the middle as the reader pulls, which is the one
            // gesture that says *a boundary is closing behind you* without a
            // word : a rule that faded in evenly would be a rule appearing, and
            // this is a rule being drawn.
            rule(drawn)

            Text("Earlier editions")
                .font(.system(.footnote, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.secondary)
                // Up from under the rule and out to its own size, so the words
                // arrive rather than switch on. Transforms and opacity only :
                // the compositor does those without a pass of its own, and a
                // blur here would be an offscreen render on every frame of the
                // gesture. See ``EditionSinking``.
                .opacity(Double(drawn * drawn))
                .scaleEffect(0.9 + 0.1 * drawn)
                .offset(y: (1 - drawn) * 12)

            rule(drawn)
        }
        .padding(.top, Editorial.rhythm * 2)
        .padding(.bottom, Editorial.rhythm)
        .frame(maxWidth: .infinity)
        // Held back against the pull, and caught up by the end of it.
        .offset(y: (1 - drawn) * Self.cling)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        // An identifier beside the words, because the words are translated and
        // a test that looked for the English would pass here and fail on a
        // device set to the reader's own language.
        .accessibilityIdentifier(Self.anchor)
    }

    private func rule(_ drawn: CGFloat) -> some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
            .scaleEffect(x: 0.12 + 0.88 * drawn, anchor: .center)
            .opacity(Double(0.35 + 0.65 * drawn))
    }
}

/// One back number, as it was.
///
/// The rows are the edition's own frozen heads rather than a read of the story
/// table : a purge that took an article shrinks a story and can tidy it away
/// altogether, and a page from last Tuesday that lost a row would be an archive
/// nobody could trust. What the world has since done to a story is not drawn
/// here at all, so nothing on a back number moves again.
struct BackNumber: View {
    let published: PublishedEdition
    let open: (UUID) -> Void

    @Environment(\.theme) private var theme

    /// What an edition says, and never more than the bound : a page published
    /// before the bound came down carries five points. See ``EditionHead``.
    private var points: [String] {
        Array(published.edition.points.prefix(EditionSummarizer.mostPoints))
    }

    /// The mark one point wears, or the tag where nothing was matched.
    private func mark(at index: Int) -> String {
        guard index < published.marks.count else { return Topic.defaultSymbol }
        return published.marks[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateline
            if !points.isEmpty { said }
            ForEach(published.stories, id: \.position) { story in
                headline(story)
                Divider()
            }
        }
        .padding(.bottom, Editorial.rhythm)
    }

    /// Which paper this is, in the words the masthead of the day used.
    ///
    /// The hour and not the moment it was written : a page that arrived at ten
    /// past eleven is still the eleven o'clock edition, and the dateline is what
    /// says so.
    private var dateline: some View {
        HStack(spacing: 6) {
            Text(published.edition.slot.title)
            Text(verbatim: "·")
            Text(published.edition.openedAt, format: .dateTime.weekday(.wide).day().month())
        }
        .font(theme.metadata)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Editorial.tightRhythm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The few points the model wrote over the whole of that page.
    private var said: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: mark(at: index))
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: EditionHead.markWidth)
                        .accessibilityHidden(true)
                    // Never cut, here as at the head of the page : the bound is
                    // on what the model writes. See ``EditionHead``.
                    Text(verbatim: point)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Editorial.rhythm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Written by the model : \(points.joined(separator: ". "))"))
    }

    private func headline(_ story: EditionStory) -> some View {
        Button {
            open(story.storyID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: story.title)
                    .font(theme.headline(.headline))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = story.summary, !summary.isEmpty {
                    StorySummary(
                        summary: summary,
                        isGenerated: story.isGenerated,
                        isTranslated: story.isTranslated,
                        style: .subheadline
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("back-number-headline")
    }
}

/// The row that asks for the next handful, by being reached.
///
/// **The reader asks by scrolling, and nothing else asks at all.** A lazy stack
/// realizes a view a little before it comes into sight, so this one is built
/// while there is still paper above it and the next pages are in hand by the
/// time the thumb gets there. Keyed on how many are already held, so each batch
/// that lands makes a new identity and the row asks once more ; without the key
/// the task would run once and the archive would stop at eight.
struct MoreBackNumbers: View {
    var body: some View {
        WaitingRing(side: 16)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Editorial.rhythm)
            .accessibilityLabel(Text("Loading earlier editions"))
    }
}
