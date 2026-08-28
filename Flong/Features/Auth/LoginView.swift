//
//  LoginView.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Collects the instance and its API credentials.
struct LoginView: View {
    @Environment(SessionModel.self) private var session

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    private enum Field: Hashable {
        case server, username, password
    }

    @FocusState private var focused: Field?

    private var canSubmit: Bool {
        !session.isSigningIn
            && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server") {
                        TextField("Server", text: $server, prompt: Text(verbatim: "rss.example.com"))
                            .labelsHidden()
                            .focused($focused, equals: .server)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            #endif
                            .onSubmit { focused = .username }
                    }

                    LabeledContent("Username") {
                        TextField("Username", text: $username, prompt: Text(verbatim: "alice"))
                            .labelsHidden()
                            .focused($focused, equals: .username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                            .onSubmit { focused = .password }
                    }

                    LabeledContent("API password") {
                        SecureField("API password", text: $password, prompt: Text(verbatim: ""))
                            .labelsHidden()
                            .focused($focused, equals: .password)
                            .textContentType(.password)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(submit)
                    }
                } header: {
                    Text("FreshRSS account")
                } footer: {
                    Text(
                        """
                        The API password is set in FreshRSS under Profile and differs from the web password. \
                        Enable the API first under Settings, Authentication.
                        """
                    )
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Text("Connect")
                            if session.isSigningIn {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!canSubmit)

                    if let signInError = session.signInError {
                        Label(signInError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Label(
                        "Your credentials are stored in the keychain and shared with your other devices through iCloud Keychain.",
                        systemImage: "icloud"
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Flong")
            .textSelection(.enabled)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task { await session.signIn(server: server, username: username, password: password) }
    }
}

#Preview {
    LoginView()
        .environment(SessionModel(store: InMemoryCredentialStore()))
}
