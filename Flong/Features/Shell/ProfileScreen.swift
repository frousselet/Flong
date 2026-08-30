//
//  ProfileScreen.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
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

/// Who is reading, as far as this device is concerned.
///
/// **There is no account here and this is not one.** Section 3 says there is no
/// server and nothing to sign in to, and a name typed into a feed reader is not
/// an exception to that : the name and the picture are the reader's own, kept
/// in the reader's own iCloud beside their other preferences, and there is
/// nowhere for them to be sent. What they buy is that a device the reader picks
/// up looks like theirs, which is the whole of it.
///
/// Everything on the page is optional and nothing is asked for twice. A reader
/// who never opens this screen gets a generic face and an application that
/// works exactly as well.
struct ProfileScreen: View {
    @Bindable var model: AppModel

    @State private var isNotAnImage = false

    #if os(iOS)
        @State private var chosen: PhotosPickerItem?
    #else
        @State private var isChoosingFile = false
    #endif

    var body: some View {
        Form {
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

            Section {
                TextField("First name", text: $model.firstName)
                TextField("Last name", text: $model.lastName)
            } header: {
                Text("Your name")
            } footer: {
                Text("Kept on your own devices, through your iCloud. Flong has no account and nowhere to send them.")
            }
        }
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Profile"))
        .alert(Text("That file is not an image"), isPresented: $isNotAnImage) {
            Button("OK", role: .cancel) {}
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
}
