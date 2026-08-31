//
//  PullToRefresh.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// The gesture a page answers to, borrowed from UIKit.
///
/// **`refreshable` was tried, and on this page it does nothing at all.**
/// SwiftUI draws its own control for a `List` ; on a `ScrollView` the modifier
/// is accepted and unreliable, and on this one, a lazy stack with a pinned
/// header, a scroll position binding and an edge effect, no control ever
/// appeared. The reader pulled and the page did not flinch, while the command
/// in the menu, which asked the model for exactly the same work, always did.
/// That is
/// the whole of the difference the reader was seeing : one of the two was never
/// being called.
///
/// So the control is the one UIKit has always had, and which every application
/// that needs this on a scroll view ends up reaching for. This view is placed
/// in the content of the scroll view, finds the scroll view it is inside by
/// walking up from itself, and hands it a `UIRefreshControl`. It draws nothing
/// and takes no room : it is a point of contact and not a thing on the page.
///
/// It taps under the finger when it takes. The control emits nothing of its
/// own, the system's lists add theirs and SwiftUI's modifier added one, so a
/// page that borrows the control borrows that too : a gesture that answers with
/// a picture and nothing felt is a gesture the reader is not sure they made.
///
/// iOS only. A Mac has no pull and, since the command came out of the reader's
/// menu, nothing there asks by hand at all : it keeps up through the clock
/// while a window sits open, the full pass at rest on the mains, and the
/// watcher that follows the store.
struct PullToRefresh: View {
    /// What the gesture asks for. The control spins until it returns.
    let action: @MainActor () async -> Void

    @ViewBuilder
    var body: some View {
        #if os(iOS)
            Bridge(action: action)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        #endif
    }
}

#if os(iOS)

    /// The one point where UIKit is reached for.
    private struct Bridge: UIViewRepresentable {
        let action: @MainActor () async -> Void

        func makeCoordinator() -> Coordinator { Coordinator(action) }

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            // It is in the content only to find its way to the scroll view, and
            // a view that swallowed touches there would be a hole in the page.
            view.isUserInteractionEnabled = false
            context.coordinator.attach(from: view)
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {
            context.coordinator.action = action
            context.coordinator.attach(from: view)
        }

        final class Coordinator: NSObject {
            var action: @MainActor () async -> Void

            private let control = UIRefreshControl()
            private weak var scrollView: UIScrollView?

            /// The tap under the finger when the gesture takes.
            ///
            /// `UIRefreshControl` emits none of its own : the system's own
            /// lists add theirs, and SwiftUI's `refreshable` added one, so a
            /// page that borrows the control has to borrow that too or the
            /// gesture answers with a picture and nothing felt.
            ///
            /// Light rather than medium. It is an acknowledgement and not an
            /// event : a heavy tap for a page being fetched is the device
            /// making more of it than the reader did.
            private let tap = UIImpactFeedbackGenerator(style: .light)

            init(_ action: @escaping @MainActor () async -> Void) {
                self.action = action
                super.init()
                control.addTarget(self, action: #selector(pulled), for: .valueChanged)
            }

            /// Finds the scroll view this sits in and hands it the control.
            ///
            /// Asked again on every update, and answered once. A view has no
            /// superview at the moment it is made : the one it will have is the
            /// scroll view's own content view, and that arrives a layout pass
            /// later, which is what the hop is for.
            func attach(from view: UIView) {
                guard scrollView == nil else { return }

                Task { @MainActor [weak self] in
                    guard let self, scrollView == nil else { return }

                    var next = view.superview
                    while let current = next {
                        if let scroll = current as? UIScrollView {
                            scrollView = scroll
                            scroll.refreshControl = control
                            // Warmed here rather than at the pull : the engine
                            // takes a moment to wake, and one woken at the
                            // moment it is used answers late enough to feel
                            // like a different gesture.
                            tap.prepare()
                            return
                        }
                        next = current.superview
                    }
                }
            }

            /// The control spins until the work returns, which is what tells the
            /// reader the gesture was heard.
            @objc private func pulled() {
                tap.impactOccurred()

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await action()
                    control.endRefreshing()
                    tap.prepare()
                }
            }
        }
    }

#endif
