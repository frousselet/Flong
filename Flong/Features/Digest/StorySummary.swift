//
//  StorySummary.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What happened, in one sentence, marked where a model is what wrote it.
///
/// **The mark stands in front of the line rather than at the end of the row.**
/// It used to be a pair of sparkles among the facts, at the far end of the
/// line that counts the rooms and says how long ago the last article came :
/// the width of the row away from the sentence it was about, in the company of
/// everything the store knows for certain. A reader who wanted to know who
/// wrote the words they were reading had to look somewhere else and then work
/// out that it referred back.
///
/// In front of the sentence it is about, it is read in the half second before
/// the sentence is, which is when it matters and the only time it does : this
/// line was written here, on this device, out of the articles underneath. The
/// glyph is a summary rather than a spark, since what it marks is a summary and
/// not a piece of magic.
///
/// **Set into the line, and not stood beside it.** It was in a column of its
/// own first, the sentence indented past it. That is a label pinned next to a
/// paragraph : it holds a gutter open down the whole page, it takes the width
/// away from the words at the one size where they have least to spare, and a
/// summary of three lines reads as a quotation. Inline, the glyph is the first
/// thing in the sentence and the wrapped lines come back to the margin under
/// it, which is how Mail sets the same mark on the same kind of line, and it is
/// the treatment the reader has already met there.
struct StorySummary: View {
    let summary: String
    /// Whether a model wrote the headline or this line. See `Story`.
    let isGenerated: Bool
    /// The step of the scale the line is set at : a row of the front page can
    /// spare less than a story's own page.
    var style: Font.TextStyle = .subheadline
    /// How many lines a row allows it, or none where the page gives it all it
    /// needs.
    var lines: Int?

    @Environment(\.theme) private var theme

    var body: some View {
        line
            .font(theme.standfirst(style))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The glyph inside the words is not a word, and VoiceOver reads
            // nothing where the eye reads a mark. Said here instead, in front
            // of the sentence, in the order the page says it.
            .accessibilityLabel(
                isGenerated ? Text("Written by the model. \(summary)") : Text(verbatim: summary)
            )
            .help(isGenerated ? Text("Written by the model") : Text(verbatim: ""))
    }

    /// The sentence, with the mark of who wrote it at the head of it.
    ///
    /// **One `Text` and not two views.** A glyph that is part of a sentence has
    /// to break with the sentence : the second line of a summary starts at the
    /// margin, under the mark, rather than in a column the mark opened. Only a
    /// single run of text does that.
    ///
    /// The concatenation is deprecated and its replacement is not usable here :
    /// interpolating into a `Text` means interpolating into a localized key, and
    /// a story's summary is written by a model on this device and translated by
    /// nobody, so the key would be `%@ %@` in the catalogue. The tick at the end
    /// of a read headline is built exactly this way, a screen away in
    /// ``ArticleRow``.
    private var line: Text {
        let sentence = Text(verbatim: summary)
        guard isGenerated else { return sentence }

        // A step quieter than the words it stands in front of : it says who
        // wrote them and is not one of them.
        return Text(Image(systemName: "text.line.3.summary")).foregroundStyle(.tertiary)
            + Text(verbatim: " ") + sentence
    }
}
