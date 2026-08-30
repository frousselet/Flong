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
struct CollectionsScreen: View {
    let model: AppModel
    let menu: (Route) -> Void
    let open: (LibraryCollection.Kind) -> Void

    private static let square = GridItem(.adaptive(minimum: 150), spacing: 16)

    @State private var isNaming = false
    @State private var named = ""

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [Self.square], spacing: 18) {
                section(nil, of: marked)

                // The band the reader made, and the way to add to it. The
                // heading is drawn whether or not there is anything under it,
                // unlike the others : a reader with no collections is exactly
                // the reader who needs to be shown where they are made.
                Section {
                    ForEach(mine) { collection in
                        Button {
                            open(collection.kind)
                        } label: {
                            CollectionSquare(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        named = ""
                        isNaming = true
                    } label: {
                        NewCollectionSquare()
                    }
                    .buttonStyle(.plain)
                } header: {
                    heading("My collections")
                }

                section("By month", of: months)
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
        .task { await model.loadCollections() }
    }

    /// One band of squares, which draws nothing at all when it holds nothing.
    ///
    /// A band with no title draws no heading either, which is what puts the
    /// favourites at the top of the page rather than inside something.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey?, of collections: [LibraryCollection]) -> some View {
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

    /// What the reader marked, which every reader has and nobody made.
    private var marked: [LibraryCollection] {
        model.collections.filter { $0.kind == .starred || $0.kind == .annotated }
    }

    /// What the reader made.
    private var mine: [LibraryCollection] {
        model.collections.filter { if case .made = $0.kind { true } else { false } }
    }

    private var months: [LibraryCollection] {
        model.collections.filter { if case .month = $0.kind { true } else { false } }
    }
}

/// One square : a picture of what is inside, and what it is called under it.
///
/// The name goes below the picture rather than on it. A caption laid over a
/// photograph has to be given a scrim to stay readable, and a scrim is a thing
/// between the reader and the picture they came to recognize.
struct CollectionSquare: View {
    let collection: LibraryCollection

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

    static func name(of kind: LibraryCollection.Kind) -> Text {
        switch kind {
        case .starred: Text("Starred")
        case .annotated: Text("Notes")
        case .made(let name): Text(verbatim: name)
        case .month(let month): Text(month, format: .dateTime.month(.wide).year())
        }
    }

    private static func mark(of kind: LibraryCollection.Kind) -> String {
        switch kind {
        case .starred: "star"
        case .annotated: "text.quote"
        case .made: "folder"
        case .month: "calendar"
        }
    }
}

/// The square that makes a new collection.
///
/// It sits at the end of the reader's own band rather than in a toolbar, the
/// way an album is added in Photos : the place a thing is made is the place
/// the things of that kind already are.
struct NewCollectionSquare: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

            Text("New collection")
                .font(.system(.subheadline, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
