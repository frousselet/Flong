//
//  ArticleWebView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import OSLog
import SwiftUI
import WebKit

#if os(macOS)
    import AppKit
#endif

/// Displays an article, in a web view that can do nothing else.
///
/// Section 10 of the specification asks for an isolated view : no script
/// execution, no cookies, nothing kept between articles. The sanitizer has
/// already removed what could run ; this is the second lock, so a mistake in the
/// first one is not enough on its own.
struct ArticleWebView {
    let html: String

    /// Said once the page has finished, with the document that finished.
    ///
    /// A web view is done when its main frame is, which is after the pictures
    /// in it have arrived : it is the moment a page stops moving under the
    /// reader, and therefore the moment there is something worth showing them.
    /// See ``ArticlePage``, which is what waits for it.
    var onLoad: ((String) -> Void)?

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        #if os(iOS)
            configuration.allowsInlineMediaPlayback = true
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.isInspectable = false
        // **Nothing of its own behind the page.** A web view paints white
        // under whatever it is showing, which is a white flash before the
        // article on a dark page and a white band past the end of it when the
        // reader pulls. What shows through instead is the paper the screen is
        // already painted in, which is the paper the document states.
        webView.underPageBackgroundColor = .clear
        #if os(iOS)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
        #endif
        return webView
    }

    fileprivate func update(_ webView: WKWebView, coordinator: Coordinator) {
        // Kept up to date rather than handed over once : the closure is a new
        // one on every pass of the body it was written in.
        coordinator.onLoad = onLoad

        guard coordinator.html != html else { return }
        coordinator.html = html
        // No base address is given : a relative link in a body that escaped the
        // sanitizer must not resolve to anything.
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps links out of the reader.
    ///
    /// An article is read here ; a link goes to the browser, which is where the
    /// reader expects the rest of the web to happen.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var onLoad: ((String) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished()
        }

        /// A load that failed is a load that is over.
        ///
        /// Nothing here is fetched from a network, so this is all but
        /// unreachable ; unreachable and silent is a page that never appears,
        /// which is worse than a page that appears wrong.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finished()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finished()
        }

        private func finished() {
            guard let html else { return }
            onLoad?(html)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            guard url.scheme?.hasPrefix("http") == true || url.scheme == "mailto" else { return }

            #if os(macOS)
                NSWorkspace.shared.open(url)
            #else
                UIApplication.shared.open(url)
            #endif
        }
    }
}

#if os(macOS)
    extension ArticleWebView: NSViewRepresentable {
        func makeNSView(context: Context) -> WKWebView {
            makeWebView(coordinator: context.coordinator)
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            update(webView, coordinator: context.coordinator)
        }
    }
#else
    extension ArticleWebView: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView {
            makeWebView(coordinator: context.coordinator)
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            update(webView, coordinator: context.coordinator)
        }
    }
#endif
