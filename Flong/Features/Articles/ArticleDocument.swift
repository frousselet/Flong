//
//  ArticleReaderView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Builds the page an article is displayed as.
///
/// The article is served to an isolated web view as a document of its own, with
/// the appearance of the system baked in : section 10 of the specification asks
/// for rendered HTML to follow light and dark mode, which `color-scheme` and a
/// `prefers-color-scheme` block are exactly what does.
nonisolated enum ArticleDocument {
    /// Which of the two bodies a page is built from.
    ///
    /// The feed gave one and, when the feed was short, the article's own page
    /// gave another. Both are kept, and the reader may read either : an
    /// extraction is a guess about somebody else's markup, and a guess the
    /// reader cannot get out of is a guess imposed on them.
    nonisolated enum Body: Hashable, Sendable {
        case feed
        case page
    }

    /// - Parameter publisher: who published it, as the application names them
    ///   everywhere else : the group rather than the feed it arrived through.
    ///   The feed's own title stands in only where the publisher is unknown.
    /// A picture a pill wears, and the colour that picture averages to.
    ///
    /// The two travel together because one comes from the other : the colour is
    /// worked out from the pixels of the mark when they are decoded, so there
    /// is no such thing as a tint without a picture, and a signature carrying
    /// them apart would be a signature able to say there is.
    nonisolated struct Picture: Hashable, Sendable {
        let address: URL
        /// Nothing where the mark has not been decoded on this device yet. The
        /// pill wears the neutral grey then, rather than waiting to know.
        var tint: Tint?
    }

    /// - Parameter mark: the publisher's own mark, to set in the pill in front
    ///   of their name. One address and no second try : see ``SourceIcon/mark(for:)``.
    /// - Parameter portraits: a picture for a person who is credited, by the
    ///   name they are credited under.
    ///
    ///   **Nothing fills this yet, and the pills are built to be filled.** A
    ///   publisher draws a logo and every feed says where it is ; a journalist
    ///   has a face and no feed format has a field for it, so a picture would
    ///   have to come from somewhere else : an `h-card` on the article's own
    ///   page, a Micropub author, or the reader's own choosing. Whichever of
    ///   those arrives, what it has to hand over is this, and the page already
    ///   knows what to do with it.
    static func html(
        for article: Article,
        publisher: String? = nil,
        mark: Picture? = nil,
        portraits: [String: Picture] = [:],
        showing body: Body = .page
    ) -> String {
        let credits = byline(of: article, publisher: publisher, mark: mark, portraits: portraits)
        let chosen = (body == .page ? article.extractedHTML : nil) ?? article.bodyHTML ?? ""
        let markup = without(article.imageURL, in: chosen)

        return """
            <!doctype html>
            <html lang="\(article.language ?? "en")">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>\(stylesheet)</style>
            <style>\(credits.rules)</style>
            </head>
            <body>
            \(lead(of: article))
            <div class="column">
            <header>
            <h1>\(HTMLEntities.escape(article.title))</h1>
            <div class="byline">\(credits.rows)</div>
            </header>
            <article>\(markup)</article>
            </div>
            </body>
            </html>
            """
    }

    /// The picture the article is headed with, running the whole width.
    ///
    /// **Above the headline and under the controls.** It is the same picture
    /// the row the reader tapped was carrying, so the page opens on what they
    /// were looking at when they decided to open it. The controls float over
    /// it, which is what the width is for : a picture inset inside the column
    /// with a bar of its own above it would be a photograph with a shelf on it.
    ///
    /// **Its own height, and no crop.** Every other picture in the application
    /// is shown at three by two, which is what makes a list of them read as a
    /// column ; a page is not a list, and it is the only place a photograph is
    /// looked at rather than glanced at. A portrait cropped to a landscape box
    /// on the one screen where there is room for it is a crop made for nothing.
    ///
    /// It also means the head takes no room until there is something to put in
    /// it : a box reserved at a ratio is a box that is empty while the picture
    /// loads and stays empty if it never arrives.
    private static func lead(of article: Article) -> String {
        guard let address = article.imageURL, HTTPURL.isFetchable(address) else { return "" }
        let source = HTMLEntities.escape(address.absoluteString)
        return "<figure class=\"lead\"><img src=\"\(source)\" alt=\"\"></figure>"
    }

    /// The body without the picture the page is already headed with.
    ///
    /// An article's picture is taken from the feed or, failing that, from the
    /// first picture in its body : in the second case the head and the first
    /// paragraph would be the same photograph twice, one above the other. What
    /// is removed is the tag and nothing around it ; an empty `figure` left
    /// behind is drawn as nothing, which the stylesheet sees to.
    static func without(_ picture: URL?, in markup: String) -> String {
        guard let address = picture?.absoluteString, !address.isEmpty else { return markup }
        guard let found = markup.range(of: address) else { return markup }

        // Back to the `<` that opens the tag holding it, and on to the `>` that
        // closes it. Anything else between them is that tag's own business.
        let before = markup.startIndex..<found.lowerBound
        let after = found.upperBound..<markup.endIndex

        guard let opening = markup.range(of: "<img", options: [.backwards, .caseInsensitive], range: before),
            let closing = markup.range(of: ">", range: after)
        else { return markup }

        return markup.replacingCharacters(in: opening.lowerBound..<closing.upperBound, with: "")
    }

    /// Where it came from and when, then who wrote it : two lines, each name
    /// on a pill of its own.
    ///
    /// **A person is not a date.** The author used to sit in a run of
    /// punctuation with the publication and the revision, which put a name
    /// between two timestamps and gave it the weight of one. The first line is
    /// the piece as a whole : who ran it and when. The second is who wrote it,
    /// and it is the only thing on it.
    ///
    /// **One pill per person, never one pill per credit line.** Feeds write
    /// three names into one field and leave the reader to unpick them. Two
    /// people are two people : they are separated here so that each is a thing
    /// on the page rather than a substring, which is what a face in front of a
    /// name will need when there is one to put there.
    ///
    /// Returns the rows, and the rules that put each picture in its pill.
    private static func byline(
        of article: Article,
        publisher: String?,
        mark: Picture?,
        portraits: [String: Picture]
    ) -> (rows: String, rules: String) {
        // Numbered as they are met, since each picture needs selectors of its
        // own and both the address and the colour stay in the stylesheet rather
        // than going into an attribute, where they would be escaped twice for
        // one gain of nothing.
        var pictures: [Picture] = []

        func pill(_ name: String, wearing picture: Picture?) -> String {
            // The mark's own box is dropped when there is no picture to put in
            // it, since scripting is off and nothing in the page can notice one
            // that failed : a box kept for a picture that never arrives is a
            // hole in front of the name for the whole life of the page.
            guard let picture else {
                return "<span class=\"pill\">\(HTMLEntities.escape(name))</span>"
            }

            pictures.append(picture)
            let index = pictures.count - 1
            return
                "<span class=\"pill p\(index)\"><span class=\"mark\"></span>\(HTMLEntities.escape(name))</span>"
        }

        var lines: [String] = []

        // The first line is where it came from and when they ran it. Both are
        // facts about the piece as a whole, and the date is the shortest thing
        // a reader checks, so it sits where the eye already is.
        var first: [String] = []

        let source = publisher ?? article.domain ?? article.feedTitle
        if !source.isEmpty { first.append(pill(source, wearing: mark)) }

        var when: [String] = []
        if let date = article.publishedAt {
            when.append(date.formatted(date: .long, time: .shortened))
        }
        // Said in full here, beside the publication rather than instead of it :
        // the page has room for both, and a reader who has opened the article
        // is the one who wants to know exactly what changed when. The list has
        // room for one and shows whichever is the later.
        if let updated = article.updatedAt {
            when.append(String(localized: "updated \(updated.formatted(date: .long, time: .shortened))"))
        }
        if !when.isEmpty {
            first.append("<span>\(HTMLEntities.escape(when.joined(separator: " · ")))</span>")
        }

        if !first.isEmpty { lines.append("<div class=\"line\">\(first.joined())</div>") }

        // The second line is who wrote it. The names alone : a pill under the
        // paper that ran it, holding a person's name, is a byline, and a word
        // in front of it would be the page explaining a shape that explains
        // itself.
        let people = self.people(in: article.author ?? "")
        if !people.isEmpty {
            let pills = people.map { pill($0, wearing: portraits[$0]) }.joined()
            lines.append("<div class=\"line\">\(pills)</div>")
        }

        // The mark, and the colour the mark averages to. How much of that
        // colour the pill takes is the stylesheet's business and the same for
        // every pill ; all a generated rule says is which colour it is.
        let rules = pictures.enumerated()
            .flatMap { index, picture -> [String] in
                var rules = [".pill.p\(index) .mark { background-image: url(\"\(address(picture.address))\"); }"]
                if let tint = picture.tint { rules.append(".pill.p\(index) { --tint: \(tint.channels); }") }
                return rules
            }
            .joined(separator: "\n")

        return (lines.joined(), rules)
    }

    /// The people named in one credit line, one by one.
    ///
    /// A feed has one field for this and publishers put whole newsrooms in it,
    /// separated by whichever punctuation the template happened to use. The
    /// separators here are the ones that actually turn up : a comma, a
    /// semicolon, an ampersand, and the word for *and* in the two languages
    /// this application speaks.
    ///
    /// **Two bare words divided by a comma are left alone.** `Dupont, Jean` is
    /// one person written backwards, and splitting it produces two pills naming
    /// halves of somebody. It is a guess, and it is the guess that fails
    /// quietly : a pair of one-word stage names kept together reads as an
    /// oddity, where a surname and a forename torn apart reads as a bug.
    static func people(in line: String) -> [String] {
        let flattened =
            line
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: " & ", with: ",")
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " et ", with: ",", options: .caseInsensitive)

        let parts =
            flattened
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count == 2, parts.allSatisfy({ !$0.contains(" ") }) {
            let whole = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return whole.isEmpty ? [] : [whole]
        }

        return parts
    }

    /// An address, safe to write into the `url()` of a rule.
    ///
    /// **It comes from a feed, so it is checked before it is written.**
    /// ``SourceIcon/mark(for:)`` has already refused anything that is not an
    /// http address and raised it to TLS ; what is left is to make sure the
    /// text of it cannot close the `url()` it sits in and start a rule of its
    /// own. Percent encoding means neither character should survive that far,
    /// and neither is written out on the strength of should.
    private static func address(_ picture: URL) -> String {
        picture.absoluteString
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    /// Deliberately small : an article is text, and the reader's own settings
    /// decide the rest once section 10 typography arrives.
    private static let stylesheet = """
        :root {
          color-scheme: light dark;
          --text: #1c1c1e; --muted: #6c6c70; --rule: #d8d8dc; --link: #0b6bcb;
          --voice: -apple-system, system-ui, sans-serif;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f2f2f7; --muted: #9c9ca1; --rule: #3a3a3c; --link: #6fb2ff;
          }
          /* More of the colour on a dark page : the same wash that reads as a
             tint over paper is all but gone over black. */
          .pill {
            background: rgb(var(--tint, 120 120 128) / 30%);
            box-shadow: inset 0 0 0 0.5px rgb(var(--tint, 120 120 128) / 45%);
          }
        }
        body {
          margin: 0; padding: 0;
          /* The shorthand carries Dynamic Type ; the family after it carries the
             voice. Serif for what was written, as everywhere else. */
          font: -apple-system-body; font-family: ui-serif, "New York", Georgia, serif;
          line-height: 1.55; color: var(--text);
          -webkit-text-size-adjust: 100%; overflow-wrap: break-word;
        }
        /* The measure lives here rather than on the body, so that the picture
           at the head can run the whole width while the words do not. */
        .column { margin: 0 auto; padding: 16px; max-width: 42em; }
        /* Edge to edge, under the controls, and at whatever height its own
           shape gives it. */
        .lead { margin: 0; }
        .lead img { display: block; width: 100%; height: auto; }
        h1 { font-size: 1.6em; line-height: 1.25; margin: 0 0 8px; }
        h2, h3, h4 { line-height: 1.3; margin: 1.4em 0 0.4em; }
        /* What the application says about the article, rather than the article. */
        /* Two lines : where it came from and when, then who wrote it. */
        .byline {
          font-family: var(--voice); color: var(--muted); font-size: 0.9em; margin: 0 0 16px;
          display: flex; flex-direction: column; align-items: flex-start; gap: 6px;
        }
        .byline:empty { display: none; margin: 0; }
        .byline .line { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px; }
        /* The pill the picture credits already use. It takes the colour of what
           is under it, which on this page is paper and over a picture is the
           picture.

           And a tint of whoever it names, where their mark has been decoded
           and averaged : the amount is decided here, once, so a generated rule
           has only to say which colour. A neutral grey stands in for a pill
           whose mark is not known, which is also every pill that has none. */
        .pill {
          display: inline-flex; align-items: center; gap: 6px;
          padding: 3px 10px; border-radius: 999px;
          color: var(--text);
          background: rgb(var(--tint, 120 120 128) / 18%);
          -webkit-backdrop-filter: blur(20px) saturate(180%);
          backdrop-filter: blur(20px) saturate(180%);
          box-shadow: inset 0 0 0 0.5px rgb(var(--tint, 120 120 128) / 35%);
        }
        /* Round and ringed, as the marks are everywhere else, and tucked into
           the padding so the pill sits no taller for having one. */
        .pill .mark {
          width: 17px; height: 17px; margin: -1px 0 -1px -5px;
          border-radius: 50%; background: center / cover no-repeat;
          box-shadow: inset 0 0 0 0.5px var(--rule);
        }
        header { border-bottom: 1px solid var(--rule); padding-bottom: 12px; margin-bottom: 16px; }
        a { color: var(--link); }
        img, video, audio, iframe { max-width: 100%; height: auto; }
        figure { margin: 1em 0; }
        /* What is left where the head's own picture was taken out of the body. */
        figure:empty, p:empty { display: none; margin: 0; }
        figcaption { font-family: var(--voice); color: var(--muted); font-size: 0.85em; }
        blockquote {
          margin: 1em 0; padding: 0 0 0 1em;
          border-left: 3px solid var(--rule); color: var(--muted);
        }
        pre { overflow-x: auto; padding: 12px; background: color-mix(in srgb, var(--text) 8%, transparent); }
        code { font-family: ui-monospace, monospace; font-size: 0.9em; }
        table { display: block; overflow-x: auto; border-collapse: collapse; }
        td, th { border: 1px solid var(--rule); padding: 4px 8px; }
        hr { border: none; border-top: 1px solid var(--rule); }
        """
}
