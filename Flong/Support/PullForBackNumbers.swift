//
//  PullForBackNumbers.swift
//  Flong
//
//  Created by François Rousselet on 10/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// How far the reader has pulled past the foot of today's paper.
///
/// **An object, for the same reason the scroll offset is one.** It moves on
/// every frame of a gesture, so a screen holding it in state would rebuild the
/// whole front page as fast as the display refreshes. Read by the seam and by
/// nothing else. See ``PageOffset``.
@Observable
final class FootPull {
    /// Points past the end of the content, nought at rest and never below it.
    var pulled: CGFloat = 0
}

/// The archive is pulled for, and does not simply follow.
///
/// **A page has an end, and the reader has to mean it.** The back numbers under
/// today's paper are a year of it, and a page that slid into last November
/// because a flick carried too far would be a page nobody trusts the bottom of.
/// So today's paper ends where it ends, and what is under it is the reader
/// pulling past that end : the scroll view's own rubber band gives the
/// resistance, which is the resistance every reader already knows from the top
/// of a page, and past a threshold the archive opens and stays open.
///
/// It is the same bridge ``PullToRefresh`` is, at the other end of the page and
/// for the opposite reason : that one asks for what has not arrived yet, this
/// one asks for what has already been. Both are placed in the content of the
/// scroll view, find it by walking up from themselves, draw nothing and take no
/// room.
///
/// It taps when it takes, and the tap is the whole of what says the pull was
/// enough : the seam is drawn by the pull and completes at the same moment, so
/// the reader sees it close and feels it catch together.
///
/// iOS only. A Mac has no rubber band worth pulling and no thumb to feel a tap
/// with, so the archive is simply there : see ``AppModel/backNumbersAreOpen``.
nonisolated struct PullForBackNumbers: View {
    /// How far past the end the reader is, written on every frame.
    let pull: FootPull

    /// Said once, when the pull has gone far enough.
    let onOpen: @MainActor @Sendable () -> Void

    /// How far past the end of the page the reader has to pull.
    ///
    /// About a headline's worth. Short enough that a reader who wonders what is
    /// under the page finds out by wondering, long enough that the flick which
    /// ends today's paper does not answer the question for them.
    static let threshold: CGFloat = 96

    @ViewBuilder
    var body: some View {
        #if os(iOS)
            Bridge(pull: pull, onOpen: onOpen)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        #endif
    }
}

#if os(iOS)

    /// The one point where UIKit is reached for.
    private struct Bridge: UIViewRepresentable {
        let pull: FootPull
        let onOpen: @MainActor @Sendable () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(pull: pull, onOpen: onOpen) }

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            // It is in the content only to find its way to the scroll view, and
            // a view that swallowed touches there would be a hole in the page.
            view.isUserInteractionEnabled = false
            context.coordinator.attach(from: view)
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {
            context.coordinator.onOpen = onOpen
            context.coordinator.attach(from: view)
        }

        static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
            coordinator.letGo()
        }

        final class Coordinator: NSObject {
            private let pull: FootPull
            var onOpen: @MainActor @Sendable () -> Void

            private weak var scrollView: UIScrollView?
            private var watching: NSKeyValueObservation?

            /// Said once. The archive opens and stays open, so a reader who has
            /// asked for it is not asked to ask again on the way back down.
            private var hasOpened = false

            /// The tap when the pull takes.
            ///
            /// Soft rather than light : the pull at the top of a page
            /// acknowledges a request, and this one is a thing giving way. See
            /// ``PullToRefresh``.
            private let tap = UIImpactFeedbackGenerator(style: .soft)

            init(pull: FootPull, onOpen: @escaping @MainActor @Sendable () -> Void) {
                self.pull = pull
                self.onOpen = onOpen
            }

            /// Finds the scroll view this sits in and watches where it is.
            ///
            /// Asked again on every update and answered once, exactly as the
            /// refresh control's is : a view has no superview at the moment it
            /// is made, and the one it will have arrives a layout pass later.
            func attach(from view: UIView) {
                guard scrollView == nil else { return }

                Task { @MainActor [weak self] in
                    guard let self, scrollView == nil else { return }

                    var next = view.superview
                    while let current = next {
                        if let scroll = current as? UIScrollView {
                            scrollView = scroll
                            watch(scroll)
                            // Warmed here rather than at the pull : an engine
                            // woken at the moment it is used answers late
                            // enough to feel like a different gesture.
                            tap.prepare()
                            return
                        }
                        next = current.superview
                    }
                }
            }

            /// **Watched rather than laid out.** A view that measured its own
            /// distance past the end would be measuring a thing the scroll view
            /// is in the middle of changing ; the offset is the scroll view's
            /// own answer, and it is the one the rubber band is computed from.
            private func watch(_ scroll: UIScrollView) {
                watching = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                    MainActor.assumeIsolated { self?.moved(scroll) }
                }
            }

            private func moved(_ scroll: UIScrollView) {
                // Past the end, and never before it : a page pulled at the top
                // is being refreshed and has nothing to do with this.
                let end = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                let past = scroll.contentOffset.y - max(end, 0)

                let pulled = max(past, 0)
                if pull.pulled != pulled { pull.pulled = pulled }

                guard !hasOpened, pulled >= PullForBackNumbers.threshold else { return }
                hasOpened = true
                tap.impactOccurred()
                onOpen()
                tap.prepare()
            }

            /// Stops watching a scroll view this no longer belongs to.
            func letGo() {
                watching?.invalidate()
                watching = nil
                scrollView = nil
            }
        }
    }

#endif
