//
//  SiteLoginView.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import OSLog
import SwiftUI
import WebKit

/// Where a reader signs in to a site they subscribe to.
///
/// **The site's own page, in a web view, and nothing else.** Flong never sees a
/// password, never types one into a form, and never automates a login. The
/// reader signs in exactly as they would in a browser, on the site's own
/// interface, and what is kept afterwards is the cookies that page left behind.
///
/// That is a deliberate limit and not a shortcut : a program that fills in login
/// forms is a program that has to be told a password, and a password given to
/// this application is a password it now has to be trusted with. This way there
/// is nothing to trust it with.
///
/// The web view runs scripts, unlike the one an article is read in. A login form
/// is a real page on a real site and does not work without them ; the article
/// view is a document Flong built itself and has no business running anything.
/// The two are opposite cases and are configured opposite ways.
struct SiteLoginView: View {
    let host: String
    /// Called with the cookies the site left, when the reader says they are in.
    let finished: ([HTTPCookie]) async -> Void

    @State private var page = LoginPage()
    @State private var isCapturing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView(page: page, host: host)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(verbatim: host))
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("I am signed in", action: capture)
                            .disabled(isCapturing)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text(
                        "Sign in on the site as you normally would, then say so. Flong keeps the session, never a password."
                    )
                    .font(Editorial.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                }
        }
        #if os(macOS)
            .frame(minWidth: 620, minHeight: 560)
        #endif
    }

    /// Takes what the site left behind.
    ///
    /// There is no signal a site gives that says a reader is signed in : some
    /// redirect, some do not, some show the same page with a different menu.
    /// Asking the reader is the only honest way to know, and it costs them one
    /// tap they were going to make anyway.
    private func capture() {
        isCapturing = true

        Task {
            let cookies = await page.cookies()
            await finished(cookies)
            isCapturing = false
            dismiss()
        }
    }
}

/// The web view's own state, kept out of the SwiftUI view so that the cookies
/// can be asked for after the fact.
@MainActor
final class LoginPage {
    /// A store of its own, thrown away with the sheet.
    ///
    /// Nothing from a login lingers in a store shared with anything else : what
    /// is kept is kept deliberately, in the keychain, and the rest goes.
    let dataStore = WKWebsiteDataStore.nonPersistent()

    func cookies() async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies()
    }
}

private struct LoginWebView {
    let page: LoginPage
    let host: String

    fileprivate func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = page.dataStore
        // A login form is a real page on a real site : it does not work without
        // scripts, and this is the one place in the application that runs them.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = false

        if let url = URL(string: "https://\(host)/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
}

#if os(iOS)
    extension LoginWebView: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView { makeWebView() }
        func updateUIView(_ webView: WKWebView, context: Context) {}
    }
#else
    extension LoginWebView: NSViewRepresentable {
        func makeNSView(context: Context) -> WKWebView { makeWebView() }
        func updateNSView(_ webView: WKWebView, context: Context) {}
    }
#endif
