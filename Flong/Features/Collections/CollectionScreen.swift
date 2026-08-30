//
//  CollectionScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One square, opened.
///
/// The same column and the same rows as everywhere else. A collection is not a
/// different kind of place, it is the library with one question asked of it.
struct CollectionScreen: View {
    let model: AppModel
    let kind: LibraryCollection.Kind
    let open: (UUID) -> Void

    @Namespace private var zoom

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.collectionArticles) { article in
                    ArticleRow(article: article, zoom: zoom) { open(article.id) }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(CollectionSquare.name(of: kind))
        .task { await model.loadCollection(kind) }
    }
}
