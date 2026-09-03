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
        return webView
    }

    fileprivate func update(_ webView: WKWebView, coordinator: Coordinator) {
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
