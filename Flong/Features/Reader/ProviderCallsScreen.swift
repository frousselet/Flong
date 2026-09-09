//
//  ProviderCallsScreen.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What has left this device, and what it cost.
///
/// **A page and not a number in a footer.** A count nobody can check is not a
/// log, and section 14 asks for a log. The row above carries the count, so the
/// cheap fact is on the page before this one and the whole of it is one press
/// away.
///
/// **No detail behind a row.** The row is everything that is kept, and a
/// chevron opening an empty page would suggest there is more.
struct ProviderCallsScreen: View {
    let model: AppModel
    let close: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        List {
            if model.providerCalls.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No calls yet", systemImage: "arrow.up.forward")
                    } description: {
                        Text("Nothing has been sent from this device.")
                    }
                }
            } else {
                Section {
                    ForEach(model.providerCalls) { call in
                        row(call)
                    }
                } footer: {
                    Text("What was sent is counted, never kept. Calls are kept for 90 days.")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await model.clearProviderCalls() }
                    } label: {
                        Text("Clear the log")
                    }
                    .accessibilityIdentifier("clear-provider-calls")
                }
            }
        }
        .themedRows()
        .navigationTitle(Text("Outgoing calls"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
        .task { await model.loadProviderCalls() }
    }

    /// One call : what it was for, where it went, and how it ended.
    private func row(_ call: ProviderCall) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(call.task.title)

            // Verbatim : a host and a model identifier are spelled the same in
            // every language.
            Text(verbatim: "\(call.host) · \(call.model)")
                .font(theme.metadata)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ended(call)
                if let prompt = call.promptTokens {
                    Text(verbatim: "·")
                    Text("\(prompt + (call.answerTokens ?? 0)) tokens")
                }
            }
            .font(theme.metadata)
            .foregroundStyle(call.outcome == .answered ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
        }
    }

    private func ended(_ call: ProviderCall) -> Text {
        switch call.outcome {
        case .answered:
            Text("Answered \(call.startedAt, format: .relative(presentation: .named))")
        case .declined:
            Text("Would not write about it")
        case .busy:
            Text("Busy")
        case .refused:
            Text("Refused")
        case .failed:
            Text("Failed")
        case .cancelled:
            Text("Stopped")
        }
    }
}
