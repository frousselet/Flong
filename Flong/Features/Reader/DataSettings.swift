//
//  DataSettings.swift
//  Flong
//
//  Created by François Rousselet on 03/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What this device and the reader's iCloud hold, and how to take it all back.
///
/// **One subject, and the subject is the reader's own copy of everything.** The
/// repair for a source another device stopped following, the exchange with
/// iCloud on a build being worked on, and the command that empties both : three
/// things about the same store, standing on a page named after it.
///
/// **The danger zone is at the foot of this page rather than of the panel.**
/// The panel it hangs from shows and does not act, which is what makes it
/// readable at a glance ; a command that deletes everything the reader has, on a
/// page where nothing else can be pressed, would be the one control there and
/// the loudest thing in the application. Here it is last, under the two other
/// things about the same store, and a reader arrives at it having chosen the
/// subject. `docs/technical/interface.md` records the move.
struct DataSettings: View {
    let model: AppModel
    /// The way out of the panel this page is pushed inside.
    ///
    /// **It closes the whole panel and does not merely go back.** Once
    /// everything is deleted there is nothing behind this page to return to :
    /// the reader lands on an application that looks like a first launch,
    /// rather than on a settings page reporting a success.
    let close: () -> Void

    @State private var tidy: AppModel.SourceTidy?
    @State private var isAskingToDeleteEverything = false
    @State private var isDeletingEverything = false

    var body: some View {
        Form {
            tidying

            #if DEBUG
                development
            #endif

            dangerZone
        }
        .themedRows()
        #if os(macOS)
            .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Your data"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { PanelDismiss(close: close) }
        }
        .alert("Delete everything?", isPresented: $isAskingToDeleteEverything) {
            Button("Delete everything", role: .destructive) {
                Task {
                    isDeletingEverything = true
                    await model.deleteEverything()
                    isDeletingEverything = false
                    close()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your subscriptions, every article, everything you kept and every site you are signed in to, on this device and in your iCloud. This cannot be undone. Another device that still has them will put its own copy back."
            )
        }
        .alert(
            tidyTitle,
            isPresented: Binding(get: { tidy != nil }, set: { if !$0 { tidy = nil } }),
            presenting: tidy
        ) { answer in
            if case .stranded(let feeds) = answer {
                Button("Remove", role: .destructive) {
                    Task { await model.removeSources(feeds) }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { answer in
            switch answer {
            case .stranded(let feeds):
                // The names are the publishers' own and are not translated.
                Text(
                    "Your iCloud no longer has these, so another device stopped following them. Removing one takes its articles with it, the ones you kept included, and cannot be undone.\n\n\(feeds.map(\.title).joined(separator: "\n"))"
                )
            case .settled:
                Text("Every source here is one your iCloud still has.")
            case .unavailable:
                Text("Nothing was changed. Try again when this device is back on the network.")
            }
        }
    }

    // MARK: - Sources another device stopped following

    /// The repair for a source removed on another device that never went here.
    ///
    /// It removes nothing on its own. What it finds is put back to the reader by
    /// name, because a source going takes its articles with it, the kept ones
    /// included, and that cannot be undone.
    private var tidying: some View {
        Section {
            Button {
                Task { tidy = await model.findSourcesRemovedElsewhere() }
            } label: {
                HStack(spacing: 8) {
                    Label("Tidy the sources", systemImage: "sparkles")
                    if model.isTidyingSources {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .accessibilityIdentifier("tidy-sources")
            .disabled(model.isTidyingSources)
        } header: {
            Text("Sources")
        } footer: {
            Text("Offers to remove the sources you stopped following on another device.")
        }
    }

    /// What the alert about the tidying is headed, which is the one thing the
    /// alert needs before it knows which answer it is showing.
    private var tidyTitle: Text {
        switch tidy {
        case .stranded: Text("Sources removed elsewhere")
        case .settled: Text("Nothing to tidy")
        default: Text("Your iCloud could not be asked")
        }
    }

    // MARK: - Starting over

    /// The one command here that takes something away for good.
    ///
    /// **A card of its own rather than another row in the form.** Everything
    /// above it is a setting or a repair, and both are things a reader changes
    /// their mind about freely ; this one is not, and a row that looks like its
    /// neighbours is a row that is pressed like its neighbours. So it leaves the
    /// grouped background entirely and stands on red glass, which is the one
    /// place in the application the material is used to say danger rather than
    /// to float over a page. `docs/technical/interface.md` records why the
    /// exception is allowed here and nowhere else.
    ///
    /// **It says what it will do before it does it, and it is honest about what
    /// it cannot do.** There is no server and no account : deleting the zone and
    /// the archive empties the reader's iCloud, and a second device that still
    /// holds the subscriptions will recreate the zone and put its copy back.
    /// Promising otherwise would be promising a reach Flong does not have.
    private var dangerZone: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    // The mark is the red thing in the heading and the words are
                    // not : a title in red on a red wash is a title read with
                    // effort, and this is the one heading in the application
                    // that has to be read.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Danger zone")
                }
                .font(.headline)

                Text(
                    "Deletes every subscription, every article and everything you kept, here and in your iCloud. Flong starts again as it was on its first day."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    isAskingToDeleteEverything = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Delete everything")
                        if isDeletingEverything {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(isDeletingEverything)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A wash and not a coat. Tinted at full strength the glass stops
            // being glass : it is a flat red block, nothing of the page shows
            // through it, and the solid red of the button it holds disappears
            // into it. A third of the colour leaves the material doing its own
            // work and leaves the one control in the card the strongest red on
            // screen, which is the right way round.
            .glassEffect(.regular.tint(.red.opacity(0.3)), in: .rect(cornerRadius: 26))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - What only a build being worked on has

    /// The exchange with iCloud, on demand.
    ///
    /// A development command, and only there. The engine decides when to send
    /// and when to fetch and is right far more often than a button would be :
    /// this is for watching an exchange happen on demand while something is
    /// being built. It forgets the change tokens, the tags the server gave each
    /// record and the archives already read, then sends and fetches the whole
    /// of the zone, which is the repair path and spends the record budget of
    /// section 7 in one go. That is why it does not ship.
    #if DEBUG
        private var development: some View {
            Section {
                Button {
                    Task { await model.forceSynchronization() }
                } label: {
                    Label("Force a synchronization", systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
        }
    #endif
}
