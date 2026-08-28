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

/// Bench for the Google Reader layer : one row per endpoint, run against the
/// signed-in account.
struct ProbeView: View {
    @Environment(SessionModel.self) private var session
    @State private var model = ProbeModel()

    var body: some View {
        @Bindable var model = model

        Form {
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
            } footer: {
                Text("Read checks never change anything on the account.")
            }

            Section {
                Button(action: run) {
                    HStack {
                        Text(model.hasRun ? "Run again" : "Run the checks")
                        if model.isRunning {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(model.isRunning || session.provider == nil)
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

    private func run() {
        guard let provider = session.provider, !model.isRunning else { return }
        Task { await model.run(with: provider) }
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
    NavigationStack {
        ProbeView()
            .environment(SessionModel(store: InMemoryCredentialStore()))
    }
}
