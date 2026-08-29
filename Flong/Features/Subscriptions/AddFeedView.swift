//
//  AddFeedView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Follows a feed from an address.
///
/// The address of a site is accepted as readily as the address of a feed : the
/// page is asked where its feed is, and the usual locations are tried after
/// that, so a reader never has to go looking for the exact URL themselves.
struct AddFeedView: View {
    let add: (String) async -> Void

    @State private var address = ""
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $address) {
                        Text("Address of a feed or of a site")
                    }
                    .focused($isFocused)
                    .disabled(isWorking)
                    #if os(iOS)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                } footer: {
                    Text("Flong reads the page to find its feed when the address is not one already.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Add a feed"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: submit)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .onAppear { isFocused = true }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 220)
        #endif
    }

    private func submit() {
        guard !isWorking else { return }
        isWorking = true

        Task {
            await add(address)
            isWorking = false
            dismiss()
        }
    }
}
