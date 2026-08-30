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
/// two squares everybody has is a heading that says nothing : favourites is
/// what they starred and notes is what they wrote on. Then what they made
/// themselves, under their own name. Then the months, which fall out of when a
/// copy was kept and cost the reader nothing to maintain.
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
            LazyVGrid(columns: [Self.square], spacing: 18) {
                section(nil, of: builtIn)
                section("My collections", of: mine)
                section("Dynamic collections", of: dynamic)
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Collections"))
        .toolbar {
            ToolbarItem(placement: .sectionLeading) {
                SourcesButton(open: menu)
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
            ToolbarItem(placement: .primaryAction) {
                ReaderMenu(model: model, open: menu)
            }
        }
        .overlay {
            if model.collections.isEmpty {
                ContentUnavailableView {
                    Label("Nothing kept yet", systemImage: "folder")
                } description: {
                    Text("Star an article, or write a note on one, and it is kept here for good.")
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
    }

    /// One band of squares, which draws nothing at all when it holds nothing.
    ///
    /// A band with no title draws no heading either, which is what puts the
    /// favourites at the top of the page rather than inside something.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey?, of collections: [ArticleCollection]) -> some View {
        if !collections.isEmpty {
            Section {
                ForEach(collections) { collection in
                    Button {
                        open(collection.kind)
                    } label: {
                        CollectionSquare(collection: collection)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if let title { heading(title) }
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
}

/// One square : a picture of what is inside, and what it is called under it.
///
/// The name goes below the picture rather than on it. A caption laid over a
/// photograph has to be given a scrim to stay readable, and a scrim is a thing
/// between the reader and the picture they came to recognize.
struct CollectionSquare: View {
    let collection: ArticleCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover

            VStack(alignment: .leading, spacing: 1) {
                Self.name(of: collection.kind)
                    .font(.system(.subheadline, weight: .medium))
                    .lineLimit(1)
                Text("\(collection.count) articles")
                    .font(Editorial.metadata)
                    .foregroundStyle(.secondary)
            }
        }
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
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    if collection.cover != nil {
                        RemoteImage(url: collection.cover, aspect: 1, corner: 0)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }

    static func name(of kind: ArticleCollection.Kind) -> Text {
        switch kind {
        case .builtIn(.starred): Text("Starred")
        case .builtIn(.annotated): Text("Notes")
        case .made(let name), .dynamic(let name): Text(verbatim: name)
        }
    }

    private static func mark(of kind: ArticleCollection.Kind) -> String {
        switch kind {
        case .builtIn(.starred): "star"
        case .builtIn(.annotated): "text.quote"
        case .made: "folder"
        // Described rather than filled, and the mark says which : a reader who
        // wonders why articles appear in one they never touched has been told.
        case .dynamic: "line.3.horizontal.decrease.circle"
        }
    }
}
