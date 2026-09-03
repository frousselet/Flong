//
//  ProfileSettings.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

#if os(iOS)
    import PhotosUI
#else
    import UniformTypeIdentifiers
#endif

/// Who the reader is : a face, a name, and the region they read from.
///
/// **All three are optional and none of them is asked for twice.** There is no
/// account and nothing to sign in to, so nothing here is a field somebody has
/// to fill : a reader who never opens this page keeps the generic face and an
/// application that works exactly as well. What the three buy is that a device
/// the reader picks up looks like theirs, and that a later feature can serve
/// them the edition of the place they live in.
///
/// It is a page of its own because it is one subject. The panel it hangs from
/// shows the answers ; this is the only place they are given.
struct ProfileSettings: View {
    @Bindable var model: AppModel
    /// The way out of the panel this page is pushed inside.
    let close: () -> Void

    @Environment(\.theme) private var theme

    @State private var isNotAnImage = false
    @State private var isChoosingPlace = false

    #if os(iOS)
        @State private var chosen: PhotosPickerItem?
    #else
        @State private var isChoosingFile = false
    #endif

    var body: some View {
        Form {
            face
            name
            whereabouts
        }
        .themedRows()
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Profile"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
        .alert(Text("That file is not an image"), isPresented: $isNotAnImage) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $isChoosingPlace) {
            PlacePicker(model: model)
        }
    }

    // MARK: - The face

    private var face: some View {
        Section {
            HStack {
                Spacer(minLength: 0)
                ReaderMark(model: model, side: 96)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            picker

            if model.picture != nil {
                Button(role: .destructive) {
                    model.setPicture(nil)
                } label: {
                    Text("Remove the picture")
                }
            }
        }
    }

    /// Where a picture comes from, which is not the same place on each platform.
    ///
    /// A face on a phone is in the photo library, and the picker Apple provides
    /// runs outside the application, so nothing here ever sees the library
    /// itself and no permission is asked for. A face on a Mac is a file, and a
    /// Mac reader offered a photo library instead of the open panel would be
    /// offered the wrong drawer.
    @ViewBuilder
    private var picker: some View {
        #if os(iOS)
            PhotosPicker(selection: $chosen, matching: .images, photoLibrary: .shared()) {
                Text("Choose a picture")
            }
            .onChange(of: chosen) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    take(data)
                    chosen = nil
                }
            }
        #else
            Button("Choose a picture") { isChoosingFile = true }
                .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    // The panel hands back a file this application has no other
                    // right to read, and the right lasts exactly as long as it
                    // is held.
                    let opened = url.startAccessingSecurityScopedResource()
                    defer { if opened { url.stopAccessingSecurityScopedResource() } }
                    take(try? Data(contentsOf: url))
                }
        #endif
    }

    private func take(_ data: Data?) {
        guard let data, model.setPicture(data) else {
            isNotAnImage = true
            return
        }
    }

    // MARK: - The name

    private var name: some View {
        Section {
            TextField("First name", text: $model.firstName)
            TextField("Last name", text: $model.lastName)
        } header: {
            Text("Your name")
        }
    }

    // MARK: - Where they read from

    /// Where the reader reads from, which is a fact about them like their name.
    ///
    /// **A town and a country, and never a street or a coordinate.** It sits on
    /// the reader's own page because it belongs to the person rather than to any
    /// feed, and it is as coarse as it is because the question is which region
    /// somebody reads from. ``Place`` records why nothing finer is kept.
    ///
    /// **One row that opens the picker, rather than two fields.** A town typed
    /// by hand is a spelling, and two readers who both live in Lyon would
    /// spell it two ways ; what the picker gives back is a place MapKit
    /// recognizes, with the country code that goes with it. The row shows what
    /// was chosen, and taking it back is a line of its own so that it is never
    /// done by pressing the same row twice.
    private var whereabouts: some View {
        Section {
            Button {
                isChoosingPlace = true
            } label: {
                HStack(spacing: 12) {
                    // The name of the row is what has to stay whole : a long
                    // town truncates, and a label that gave up half of itself
                    // to one would leave the row saying nothing at all.
                    Text("City and country")
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Group {
                        if let place = model.place {
                            // Verbatim : a place name is a proper noun, and the
                            // catalogue is for what Flong says rather than for
                            // what MapKit named a town.
                            Text(verbatim: place.line)
                        } else {
                            Text("Not set")
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    Image(systemName: "chevron.forward")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if model.place != nil {
                Button(role: .destructive) {
                    model.setPlace(nil)
                } label: {
                    Text("Remove where you are")
                }
            }
        } header: {
            Text("Where you are")
        }
    }
}
