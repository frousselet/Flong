//
//  CollectionsScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import SwiftUI

/// What the reader kept, in squares rather than in a line.
///
/// **A grid, the way a photo library is a grid.** A list is right for things
/// read one after another, which is what the stream is ; what was kept is not
/// read in order, it is gone back to, and going back to something means finding
/// it. A square carries a picture, and a picture is found faster than a line of
/// type.
///
/// **The page is in three parts, and the order of them is the argument.** What
/// the reader marked comes first and wears no heading, because a heading over
/// squares everybody has is a heading that says nothing : starred articles is
/// what they starred, favourite sources is who they singled out, and notes is
/// what they wrote on. Then what they made themselves, under their own name.
/// Then the months, which fall out of when a copy was kept and cost the reader
/// nothing to maintain.
///
/// **The first part is a line, and the rest is the grid.** The squares
/// everybody has are the same seven every time and are gone to by name ; at
/// the size of the grid they are two screenfuls of furniture standing in front
/// of the shelf the reader actually built. They are drawn small and laid in a
/// line that scrolls sideways instead, which puts what the reader made at the
/// top of their own page.
///
/// **The four favourites stand together for the same reason.** A star on an
/// article, a favourite source, a favourite author and a favourite newsmaker
/// are four judgements about four different things : the piece, who printed it,
/// who wrote it, who it is about. The last of them is the one no feed states
/// and the one a subscription cannot express.
///
/// **The two directories are the odd ones and are last for that reason.** Every
/// other square opens on a list of articles ; those two open on lists of
/// people, and the number under each counts names rather than pieces.
///
/// **A band with nothing in it is not drawn at all**, its heading included. A
/// reader who has made no collections is not shown an empty shelf with a label
/// on it : the way to make one is in the corner of the page, where the sources
/// are, and it is there whether the shelf exists or not.
struct CollectionsScreen: View {
    let model: AppModel
    let menu: (Route) -> Void
    let open: (ArticleCollection.Kind) -> Void

    private static let square = GridItem(.adaptive(minimum: 150), spacing: 16)

    @State private var isNaming = false
    @State private var isDescribing = false
    @State private var named = ""
    @State private var described = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                shelf
                LazyVGrid(columns: [Self.square], spacing: 18) {
                    section("My collections", of: mine)
                    section("Dynamic collections", of: dynamic)
                    // Last, and under a heading that says whose they are. A
                    // collection somebody else shared holds excerpts rather
                    // than the reader's own articles, and mixing it in with
                    // the shelf above would say the two are the same thing.
                    section("Shared with me", of: shared)
                }
                .padding(.horizontal, 22)
            }
            .editorialColumn()
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Collections"))
        .toolbar {
            ToolbarItem(placement: .sectionLeading) {
                SourcesButton(model: model, open: menu)
            }
            ToolbarItem(placement: .sectionLeading) {
                TopicsButton(model: model)
            }
            ToolbarItem(placement: .sectionLeading) {
                NotificationsButton(model: model)
            }
            // Beside the sources rather than opposite them : the leading corner
            // is where this page is acted on, and the trailing one belongs to
            // the reader's own menu in every section.
            // Two kinds to make, so a menu rather than a button : one the
            // reader fills article by article, one that fills itself from a
            // description.
            ToolbarItem(placement: .sectionLeading) {
                Menu {
                    Button {
                        named = ""
                        isNaming = true
                    } label: {
                        Label("New collection", systemImage: "folder")
                    }
                    Button {
                        named = ""
                        described = ""
                        isDescribing = true
                    } label: {
                        Label("New dynamic collection", systemImage: "line.3.horizontal.decrease.circle")
                    }
                } label: {
                    Label("New collection", systemImage: "plus")
                }
            }
            ReaderCorner(model: model, work: model.currentWork)
        }
        .overlay {
            if model.collections.isEmpty {
                ContentUnavailableView {
                    Label("Nothing kept yet", systemImage: "folder")
                } description: {
                    Text(
                        "Star an article, write a note on one, or choose a favourite source or author, and it shows up here."
                    )
                }
            }
        }
        .alert(Text("New collection"), isPresented: $isNaming) {
            TextField("Name", text: $named)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = named
                Task { await model.makeCollection(named: name) }
            }
        } message: {
            Text("Collections are yours to fill. An article joins one from its own menu.")
        }
        .alert(Text("New dynamic collection"), isPresented: $isDescribing) {
            TextField("Name", text: $named)
            TextField("What it is looking for", text: $described)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = named
                let query = described
                Task { await model.makeDynamicCollection(named: name, matching: query) }
            }
        } message: {
            Text("It fills itself with whatever matches, and goes on filling itself. Try `title:Swift` or `is:unread`.")
        }
        .task { await model.loadCollections() }
        // Who is in the shared ones, drawn from what is written down and then
        // corrected against iCloud : a square must not wait on a round trip
        // to know what to draw.
        .task { await model.loadShareMembers() }
    }

    /// The ones every reader has, in a line that scrolls sideways.
    ///
    /// **Small, and out of the grid.** These squares are furniture : the same
    /// seven on every device, in the same order, never added to and never
    /// removed. Given a cell the size of a collection the reader made, they
    /// take the first two screenfuls of the page and push what the reader
    /// actually built below the fold. Laid in a line at half the size they
    /// stay one glance and one reach, and the page opens on the shelf its
    /// owner filled.
    ///
    /// **A line that scrolls is right here and wrong for a suggestion.** What
    /// is off the end of this one is known before it is seen : a reader
    /// looking for their notes knows the square exists and will push the line
    /// along to reach it. Nothing here has to catch an eye that was not
    /// already looking.
    @ViewBuilder
    private var shelf: some View {
        if !builtIn.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(builtIn) { collection in
                        Button {
                            open(collection.kind)
                        } label: {
                            CollectionSquare(collection: collection, compact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            // A breath under the title. The line is the first thing in the
            // page and would otherwise hang off the bottom of the heading,
            // which reads as part of it rather than as the page beginning.
            .padding(.top, 20)
        }
    }

    /// One band of squares, which draws nothing at all when it holds nothing.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey, of collections: [ArticleCollection]) -> some View {
        if !collections.isEmpty {
            Section {
                ForEach(collections) { collection in
                    Button {
                        open(collection.kind)
                    } label: {
                        CollectionSquare(
                            collection: collection,
                            members: model.members(of: collection.kind),
                            faces: model.memberFaces
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                heading(title)
            }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, 2)
    }

    /// The ones every reader has, which nobody made and nobody can unmake.
    private var builtIn: [ArticleCollection] {
        model.collections.filter { if case .builtIn = $0.kind { true } else { false } }
    }

    /// The ones the reader filled article by article.
    private var mine: [ArticleCollection] {
        model.collections.filter { if case .made = $0.kind { true } else { false } }
    }

    /// The ones the reader described and never has to fill.
    private var dynamic: [ArticleCollection] {
        model.collections.filter { if case .dynamic = $0.kind { true } else { false } }
    }

    /// The ones somebody else made and invited the reader into.
    private var shared: [ArticleCollection] {
        model.collections.filter { if case .shared = $0.kind { true } else { false } }
    }
}

/// One square : a picture of what is inside, and what it is called under it.
///
/// The name goes below the picture rather than on it. A caption laid over a
/// photograph has to be given a scrim to stay readable, and a scrim is a thing
/// between the reader and the picture they came to recognize.
struct CollectionSquare: View {
    let collection: ArticleCollection
    /// Who is in it, for the collections that are shared. Empty for every
    /// other square, which is most of them.
    var members: [ShareMember] = []
    var faces: [String: CGImage] = [:]
    /// Drawn small, at a width of its own, for the line of built-in squares
    /// that scrolls sideways above the grid.
    var compact = false

    @Environment(\.theme) private var theme

    /// How wide a small square is.
    ///
    /// Narrow enough that three of them and the start of a fourth fit across
    /// a phone, which is what says the line goes on past the edge without
    /// anything having to announce it.
    private static let small: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            cover

            VStack(alignment: .leading, spacing: 1) {
                Self.name(of: collection.kind)
                    .font(.system(compact ? .caption : .subheadline, weight: .medium))
                    // Two lines in the small square : `Favourite newsmakers`
                    // does not fit on one at this width. The room for the
                    // second is not held open when it goes unused, since the
                    // line hangs its squares from the top and a gap under
                    // every short name would be paid for by all of them.
                    .lineLimit(compact ? 2 : 1)
                Self.count(of: collection)
                    .font(compact ? .caption2 : theme.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: compact ? Self.small : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The picture, over the mark of what the square holds.
    ///
    /// The mark is always drawn and the picture laid over it rather than
    /// instead of it : a cover that is slow, or that never answers, would
    /// otherwise leave a hole in the grid where a square should be.
    ///
    /// Square, and cropped to it. Everything else on the page is set at three
    /// by two, which is the shape a photograph arrives in ; a grid is a
    /// different argument, where equal cells are what let the eye run down it,
    /// and a square is the only shape that stays equal in both directions.
    private var cover: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: Self.mark(of: collection.kind))
                        .font(.system(size: compact ? 20 : 30))
                        .foregroundStyle(.secondary)
                    if collection.cover != nil {
                        RemoteImage(url: collection.cover, aspect: 1, corner: 0)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: compact ? 9 : 12))
            // **Who is in it, on the picture rather than under it.** The name
            // goes below because type laid over a photograph needs a scrim to
            // stay readable, and a scrim is a thing between the reader and the
            // picture ; a ringed face carries its own contrast and needs none,
            // and it says the collection is shared in the same glance that
            // says what is in it.
            .overlay(alignment: .bottomTrailing) {
                MemberPile(members: members, faces: faces)
                    .padding(7)
            }
    }

    static func name(of kind: ArticleCollection.Kind) -> Text {
        switch kind {
        case .builtIn(.starred): Text("Starred articles")
        case .builtIn(.favouriteSources): Text("Favourite sources")
        case .builtIn(.favouriteAuthors): Text("Favourite authors")
        case .builtIn(.favouriteNewsmakers): Text("Favourite newsmakers")
        case .builtIn(.annotated): Text("Notes")
        case .builtIn(.authors): Text("Authors")
        case .builtIn(.newsmakers): Text("Newsmakers")
        case .made(let name), .dynamic(let name): Text(verbatim: name)
        // Named by whoever shared it, so it is their words and not ours.
        case .shared(_, let title): Text(verbatim: title)
        }
    }

    /// What the number under the name counts.
    ///
    /// Articles, for every square but the two directories. Those open on a list
    /// of people, so the number under them has to be the number of rows the
    /// reader will find there : a square saying `1 240 articles` that opens on
    /// eighty names has told them the wrong thing before they touched it.
    private static func count(of collection: ArticleCollection) -> Text {
        switch collection.kind {
        case .builtIn(.authors): Text("\(collection.count) authors")
        case .builtIn(.newsmakers): Text("\(collection.count) newsmakers")
        default: Text("\(collection.count) articles")
        }
    }

    private static func mark(of kind: ArticleCollection.Kind) -> String {
        switch kind {
        case .builtIn(.starred): "star"
        // The mark a source wears everywhere else in the application, so the
        // square beside the star is plainly about publishers and not articles.
        case .builtIn(.favouriteSources): "dot.radiowaves.up.forward"
        // A pen, because a favourite author is about who wrote the piece and
        // not about who printed it : the mark beside the aerial says the two
        // are different judgements before the name under it does.
        case .builtIn(.favouriteAuthors): "signature"
        // A person in a frame rather than a pen : the favourite writers wear
        // the signature because what they did is sign, and these are the people
        // the pieces are pointed at.
        case .builtIn(.favouriteNewsmakers): "person.crop.rectangle.stack"
        case .builtIn(.annotated): "text.quote"
        // People rather than articles, which is what these two squares hold.
        case .builtIn(.authors): "person.2"
        case .builtIn(.newsmakers): "person.crop.rectangle.stack"
        case .made: "folder"
        // Described rather than filled, and the mark says which : a reader who
        // wonders why articles appear in one they never touched has been told.
        case .dynamic: "line.3.horizontal.decrease.circle"
        // Somebody else's, which the mark says before the band above it does :
        // a square that opens on excerpts rather than on the reader's own
        // articles should not look like the squares that do.
        case .shared: "folder.badge.person.crop"
        }
    }
}
