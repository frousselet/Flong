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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            Form {
                if model.contributesToPool == nil {
                    question
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
                "Sharing publishes the addresses of the sources you follow, and nothing else : no name, no article, nothing you wrote. The addresses that are secrets, and those carrying a parameter you marked as yours, are never published. You can stop at any time, and your list is taken back out."
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

                Text("A source is suggested once ten readers follow it, or once somebody vouched for does.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(model.poolContributors) readers have shared their sources so far.")
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
            Text("Flong asks the address for itself before following it, exactly as it would one you typed.")
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
