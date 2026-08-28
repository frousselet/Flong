//
//  ProbeView.swift
//  Flong
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Bench for the Google Reader layer : credentials in, one row per endpoint out.
struct ProbeView: View {
    @Environment(ProbeModel.self) private var model

    private enum Field: Hashable {
        case server, username, password
    }

    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server") {
                        TextField("Server", text: $model.server, prompt: Text(verbatim: "rss.example.com"))
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
                        TextField("Username", text: $model.username, prompt: Text(verbatim: "alice"))
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
                        SecureField("API password", text: $model.password, prompt: Text(verbatim: ""))
                            .labelsHidden()
                            .focused($focused, equals: .password)
                            .textContentType(.password)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(runIfPossible)
                    }
                } header: {
                    Text("Instance")
                } footer: {
                    Text(
                        """
                        The API password is set in FreshRSS under Profile and differs from the web password. \
                        Enable the API first under Settings, Authentication.
                        """
                    )
                }

                Section {
                    Toggle(isOn: $model.includesWriteCheck) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also test writing")
                            Text("Flips one article between read and unread, then puts it back.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isRunning)
                }

                Section {
                    Button(action: runIfPossible) {
                        HStack {
                            Text(model.hasRun ? "Run again" : "Run the checks")
                            if model.isRunning {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(!model.canRun)

                    if let addressError = model.addressError {
                        Label(addressError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if model.hasRun {
                    Section {
                        ForEach(model.checks) { check in
                            ProbeCheckRow(check: check)
                        }
                    } header: {
                        Text("Endpoints")
                    } footer: {
                        resultSummary
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("GReader bench")
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var resultSummary: some View {
        if model.isRunning {
            Text("Running.")
        } else if model.failureCount == 0 {
            Text("Every check passed.")
        } else {
            Text("\(model.failureCount) checks failed.")
        }
    }

    private func runIfPossible() {
        guard model.canRun else { return }
        focused = nil
        Task { await model.run() }
    }
}

/// One endpoint and its outcome.
struct ProbeCheckRow: View {
    let check: ProbeCheck

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.body)

                Text(check.endpoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(check.isFailure ? Color.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        switch check.outcome {
        case .passed(let text), .failed(let text): text
        case .pending, .running, .skipped: nil
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch check.outcome {
        case .pending:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Pending")
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Running")
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Passed")
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Failed")
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Skipped")
        }
    }
}

#Preview {
    ProbeView()
        .environment(ProbeModel(defaults: UserDefaults(suiteName: "flong.preview") ?? .standard))
}
