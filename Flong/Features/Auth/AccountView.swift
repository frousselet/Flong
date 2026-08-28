//
//  AccountView.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The signed-in account, where it is stored, and the way to the bench.
struct AccountView: View {
    @Environment(SessionModel.self) private var session

    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                if let account = session.account {
                    Section("FreshRSS account") {
                        LabeledContent("Server") {
                            Text(account.serverURL.host() ?? account.serverURL.absoluteString)
                        }
                        LabeledContent("Username") {
                            Text(account.username)
                        }
                    }
                }

                if let storage = session.storage {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(storage == .syncedAcrossDevices ? "Shared with your devices" : "This device only")
                                Text(storageDetail(for: storage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: storage == .syncedAcrossDevices ? "icloud.fill" : "iphone")
                                .foregroundStyle(storage == .syncedAcrossDevices ? Color.accentColor : .secondary)
                        }
                    } header: {
                        Text("Credentials")
                    }
                }

                Section {
                    NavigationLink {
                        ProbeView()
                    } label: {
                        Label("GReader bench", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("Runs one check per endpoint against this account.")
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingSignOut = true
                    } label: {
                        Text("Sign out")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Flong")
            .confirmationDialog(
                "Sign out of this account?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    session.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The credentials will be removed from the keychain, on this device and on the others.")
            }
        }
    }

    private func storageDetail(for storage: CredentialStorage) -> LocalizedStringResource {
        switch storage {
        case .syncedAcrossDevices:
            "Stored in iCloud Keychain, so your other devices signed in to the same Apple Account can use them."
        case .thisDeviceOnly:
            "iCloud Keychain refused the item, so they stay on this device."
        }
    }
}

#Preview {
    AccountView()
        .environment(
            SessionModel(
                store: InMemoryCredentialStore(
                    credentials: Credentials(
                        serverURL: URL(string: "https://rss.example.com")!,
                        username: "alice",
                        password: "secret"
                    )
                )
            )
        )
}
