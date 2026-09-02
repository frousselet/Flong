//
//  PopularFeedsView.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the other readers follow, offered as a third way to find a source.
///
/// **The third way in, beside an address and a file.** A reader arriving with
/// nothing has to know what to type, and a reader who has read for years still
/// finds a paper by hearing somebody mention it. This is that, counted rather
/// than editorialized : the addresses enough people follow, and the ones the
/// people the author vouches for follow.
///
/// **The question is asked here, once, and both answers are kept.** Nothing of
/// this reader's is published before they answer it, and a reader who says no
/// still sees the page : conditioning the reading on the contributing would be
/// extorting the consent rather than asking for it, and a consent extorted is
/// not one section 20 could stand behind.
struct PopularFeedsView: View {
    @Bindable var model: AppModel

    @State private var followed: Set<URL> = []
    /// The suggestion the author is looking behind, and who offered it.
    @State private var inspecting: PopularFeed?
    @State private var offerers: [String] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            Form {
                if model.contributesToPool == nil {
                    question
                } else if model.contributesToPool == true, !model.isSponsoredIntoPool {
                    waiting
                }

                if model.popularFeeds.isEmpty {
                    emptiness
                } else {
                    sources
                }
            }
            .formStyle(.grouped)
            .themedRows()
            .navigationTitle(Text("Popular feeds"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.openPopularFeeds() }
        .sheet(item: $inspecting) { feed in
            whoOffered(feed)
                .themed()
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 460)
        #endif
    }

    // MARK: - The question, asked once

    /// **Plainly, and with what it costs stated before the switch.** What is
    /// published is a list of addresses and nothing else : not a name, not an
    /// article, not a word the reader wrote. What cannot be promised is said
    /// too, since it is inherent and not a shortcoming to be tidied away : the
    /// list carries the opaque identity CloudKit stamps on anything anybody
    /// writes, so one reader's addresses are one list.
    private var question: some View {
        Section {
            // **One under the other rather than side by side.** The two
            // answers are not the same length in any language, and a row of
            // two makes the longer one wrap while the shorter sits on one
            // line, which reads as one button being the important one for a
            // reason nobody could name. Stacked they are the same width at
            // every type size.
            VStack(spacing: 10) {
                Button {
                    Task { await model.setContributingToPool(true) }
                } label: {
                    Text("Share my sources")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.setContributingToPool(false) }
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.vertical, 4)
        } header: {
            Text("This list is made by its readers")
        } footer: {
            Text(
                "Flong publishes the addresses of the sources you follow. Nothing else : not your name, not an article, not a word you wrote. A secret address is never shared, nor a source behind a password. You can stop whenever you like, and your list is taken back out."
            )
        }
    }

    /// Said here as well as in the panel, because this is where a reader is
    /// standing when they say yes and nothing appears to happen.
    @ViewBuilder
    private var waiting: some View {
        Section {
            Label {
                Text("Waiting for somebody to bring you in")
            } icon: {
                Image(systemName: "hourglass")
            }
            .foregroundStyle(.orange)

            if let identity = model.poolIdentity {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your contributor code")
                    Text(verbatim: identity)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        } footer: {
            Text(
                "Only readers somebody has brought in can add to the list. Give your code to a reader who is already in. Nothing of yours is published until then."
            )
        }
    }

    // MARK: - What there is

    private var emptiness: some View {
        Section {
            VStack(spacing: 10) {
                if model.isReadingPool {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: "person.2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

                Text("Nothing to suggest yet")
                    .font(theme.headline(.headline))

                Text("A source is suggested once ten readers follow it, or once a trusted reader does.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(model.poolContributors) readers have shared their sources.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var sources: some View {
        Section {
            ForEach(model.popularFeeds) { feed in
                row(feed)
            }
        } header: {
            Text("Followed by other readers")
        } footer: {
            Text("Flong checks the address before following it, as it does one you type.")
        }
    }

    private func row(_ feed: PopularFeed) -> some View {
        HStack(spacing: 12) {
            SourceIconView(identity: identity(of: feed), side: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if feed.isEndorsed {
                        // An `HStack` rather than a `Label` : a label inside a
                        // list aligns its title to the column the rows share,
                        // which here is a gap of nothing between the seal and
                        // the word it belongs to.
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Vouched for")
                        }
                        .foregroundStyle(.tint)
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("Followed by \(feed.subscribers) readers")
                    }

                    Text(verbatim: feed.domain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                followed.insert(feed.url)
                Task { await model.followPopular(feed) }
            } label: {
                Label {
                    Text("Follow")
                } icon: {
                    Image(systemName: "plus")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(followed.contains(feed.url))
        }
        .padding(.vertical, 2)
        .swipeActions {
            // **Only on the author's own device.** Withholding an address and
            // cutting somebody out are the two things nobody else may do, so
            // for everybody else these are not disabled controls, they are
            // controls that are not there.
            if model.mayDecideForThePool {
                Button(role: .destructive) {
                    Task { await model.block(feed.url) }
                } label: {
                    Label("Withhold", systemImage: "eye.slash")
                }

                Button {
                    inspecting = feed
                } label: {
                    Label("Who offered it", systemImage: "person.2")
                }
            }
        }
    }

    /// Who offered one address, and the way to cut one of them out.
    ///
    /// **What makes a ban aimable.** A bad suggestion is visible ; the accounts
    /// behind it are not, and an author who could see the one without the other
    /// would be reduced to withholding addresses one at a time for ever.
    private func whoOffered(_ feed: PopularFeed) -> some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(offerers, id: \.self) { code in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: code)
                                .font(.footnote)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    await model.ban(code)
                                    inspecting = nil
                                }
                            } label: {
                                Label("Ban", systemImage: "nosign")
                            }
                        }
                    }
                } header: {
                    Text(verbatim: feed.title)
                } footer: {
                    Text("Cutting one of them out also cuts everybody they brought in.")
                }
            }
            .formStyle(.grouped)
            .themedRows()
            .navigationTitle(Text("Who offered it"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { inspecting = nil }
                }
            }
        }
        .task { offerers = await model.offerers(of: feed) }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    /// What the icon loader needs, built from the row rather than from a store.
    ///
    /// This source is one nobody here follows, so there is no row behind it and
    /// no publisher in ``AppModel/publishers`` to look up. The mark is found
    /// the way it is found for a source that has just been added : off the site
    /// the pool named, and off the well-known paths under it.
    private func identity(of feed: PopularFeed) -> SourceIdentity {
        SourceIdentity(domain: feed.domain, name: feed.title, iconURL: nil, siteURL: feed.siteURL)
    }
}
