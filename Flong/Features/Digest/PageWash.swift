//
//  PageWash.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// How far a page has been scrolled, kept out of the page's own state.
///
/// **A value that moves on every frame has no business in a screen's state.**
/// It was `@State` on the screen, written from the scroll geometry, and SwiftUI
/// did exactly what it was told : every frame of a scroll invalidated the whole
/// body it was declared in. On the front page that is the stories, the pinned
/// header of subjects with a pane of glass under every pill, the toolbar and the
/// date in the title, all rebuilt as fast as the display refreshes so that one
/// gradient could move a few points. The page dropped frames under the thumb,
/// and every frame it dropped was spent redrawing something that had not
/// changed.
///
/// An object of its own, read by the wash and by nothing else. The screen hands
/// it over without ever looking at it, so the screen is never rebuilt for it,
/// and the only thing that moves is the thing that follows the scroll.
@Observable
final class PageOffset {
    var scrolled: CGFloat = 0
}

/// The light of a picture, spilled over the top of the page it belongs to.
///
/// A front page is one photograph and everything else set around it, and the
/// picture gives the page its temperature before a word of it is read. A screen
/// cannot print in colour on the paper, but it can let the picture light what
/// is above it : the head of the page, the bar over it and the title in it take
/// the colours of the photograph the page is built around.
///
/// **Two pages ask for it, and they ask with different pictures.** The front
/// page hands it the story it leads on, and the colour is spent by the time
/// that photograph comes into view. A story's own page hands it its own
/// picture, which is the very one the row that was tapped was carrying : the
/// page opens in the colour the reader pressed, and the colour carries across
/// the tap rather than starting again.
///
/// **The picture's own bands, and not one average of it.** See ``Wash`` : a
/// photograph averages its sky into its ground and comes out the colour of
/// neither.
///
/// **Under the standard theme and no other.** The other two state what the page
/// is printed on, warm paper or Solarized, and a wash over either is a second
/// opinion about the paper. The standard theme states nothing, which is the
/// whole of what it means : the page is the system's own white or black, and it
/// is the one page with room for a picture to say something. See
/// ``Theme/paints``.
///
/// **And nothing whatever where the reader has asked for more contrast.** It is
/// gentle enough to leave the largest type on the page legible over it, and it
/// is still something between that type and the paper, which is the thing
/// increased contrast is a request to stop doing.
struct PageWash: View {
    /// The picture the page is built around. No picture, no colour, no wash.
    let url: URL?

    /// How far the page has been scrolled, so the colour goes up with the head
    /// of the page it belongs to.
    ///
    /// **Given rather than taken.** The wash used to live inside the scrolling
    /// content, which moved it for free ; that is also what put it inside a
    /// rectangle narrower than the page and inside the scroll view's own clip.
    /// See the note on the frame below.
    ///
    /// **And observed rather than passed.** It arrived as a number, which made
    /// it the screen's own state and every frame of a scroll a rebuild of the
    /// screen. See ``PageOffset``.
    let offset: PageOffset

    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var wash: Wash?

    var body: some View {
        Group {
            if !theme.paints, contrast != .increased, let wash {
                // **What is drawn and what moves are two views.** The bands are
                // decided by the picture and the appearance, and change with
                // neither the scroll nor the frame ; where the whole of it sits
                // changes with every frame there is. Kept in one view, five
                // colours and the gradient over them were worked out again for
                // every frame of every scroll, to be laid down exactly where
                // they already were. Split, the frame moves a view SwiftUI can
                // see has not changed, and the drawing is done once.
                Bands(wash: wash)
                    // Up under the bar and further. The wash is laid at the
                    // top of the page's own content, which begins below the
                    // bar : left there, it would draw a hard edge across the
                    // screen at exactly the height a fade exists to make
                    // invisible. See ``rise`` for how far above that, and why.
                    .offset(y: -(Self.rise + Self.hold) - offset.scrolled)
                    // One lead giving way to another is a dissolve and not a
                    // cut : the colour of the page is not news.
                    .transition(.opacity)
                    .id(wash)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) { await read() }
    }

    /// How far above the page's own top the colour is held at full strength.
    ///
    /// The page begins under the bar, and the bar is where the colour is most
    /// wanted : a date, a large title and four glass buttons over the system's
    /// white is the one part of the screen a photograph can warm without
    /// touching a word of the page itself. This is more than the tallest bar
    /// any of the three platforms draws, so what is above the content is at
    /// full strength whatever the window is doing and the fade begins where the
    /// reader's own page begins.
    fileprivate static let hold: CGFloat = 200

    /// How far the colour fades in above all that.
    ///
    /// **A gradient has two ends and both of them have to be nothing.** The
    /// wash used to begin at full strength, which is a hard edge, and it was
    /// hidden above the bar where nothing could reach it. A pull to refresh
    /// reaches it : the gesture pushes the whole page down by a couple of
    /// hundred points, the wash goes with it, and the edge it had been keeping
    /// out of sight came out under the bar with a slab of flat colour under it.
    ///
    /// So the colour comes up out of nothing over this distance before it
    /// reaches full strength. At rest all of it is off screen and the page
    /// looks exactly as it did ; under a pull, what appears is the fade rather
    /// than the edge, and a pull long enough to reach the top of it finds
    /// nothing there, which is what was wanted in the first place.
    fileprivate static let rise: CGFloat = 300

    /// How far into the page the colour lasts.
    ///
    /// On the front page, about the subjects, the first heading and the top of
    /// the lead's picture : it is gone by the time that picture arrives, which
    /// is the point, a wash still going at the photograph being a tinted
    /// photograph rather than a lit page. On a story's page the photograph is
    /// at the top and the same distance carries the colour down beside it,
    /// running out around its foot, which is the same idea from the other end :
    /// the light comes off the picture and stops where the picture does.
    fileprivate static let fade: CGFloat = 380

    /// How much of the colour the paper takes at the top.
    ///
    /// **Measured against real pages rather than picked.** Half of it was
    /// invisible : the front page led that morning on a photograph of grey
    /// asphalt, which is what a great many news photographs are, and half of
    /// nearly nothing is nothing. A wash a reader cannot see is a wash that is
    /// not there.
    fileprivate static func strength(in scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.80 : 0.68
    }

    /// How much the saturation of a band is lifted, the least it may come out
    /// at, and how little of it there has to be for lifting it to be a lie.
    /// See ``Bands/paint(_:_:)``.
    fileprivate static let lift: Double = 2.2
    fileprivate static let floor: Double = 0.10
    fileprivate static let colourless: Double = 0.03

    /// How far past each side of its container the wash is drawn.
    ///
    /// Enough to cover the inset of a card in transition on the widest window
    /// Flong opens in. It costs nothing : the extra is gradient nobody ever
    /// sees, which is exactly the point of it.
    fileprivate static let overshoot: CGFloat = 220

    /// The whole of it, from the nothing above the bar to the nothing in the
    /// page.
    fileprivate static let height = rise + hold + fade

    /// Reads the colours of the lead's picture, fetching it if it must.
    ///
    /// The wash already on the page is left where it is until the new one
    /// arrives : a page that went white for a moment between two leads would be
    /// a page blinking at the reader.
    private func read() async {
        guard let url else {
            wash = nil
            return
        }

        let read = try? await ImageStore.shared.wash(at: url)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.5)) { wash = read }
    }
}

/// The colour itself, which the scroll never touches.
///
/// A view of its own so that a page being scrolled moves it rather than draws
/// it again : it holds the picture's bands and the appearance and nothing else,
/// so SwiftUI can see across a frame that nothing about it has changed and
/// leave the gradient where it is. See the note in ``PageWash/body``.
private struct Bands: View {
    let wash: Wash

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .frame(height: PageWash.height)
            // **Wider than whatever holds it.** The width of the window rather
            // than of the column, since the page holds its type to a measure
            // and light is not held to anything, and then ``PageWash/overshoot``
            // past that on each side.
            //
            // A transition is what needs it. A push and the article sheet both
            // turn a screen into an inset, rounded card, and a card is narrower
            // than the container the wash sized itself against : the wash's own
            // vertical edge then falls inside the card and reads as a band of
            // colour stopping in the middle of the page. Drawn past every edge
            // there is no edge of it left to see : the card crops it, the way a
            // window crops what is behind it.
            //
            // **The width of the page, because it is the page's own background
            // now.** It used to be the background of the column of type, which
            // is held to a measure and inset by its own margins : a rectangle
            // narrower than the page, inside a scroll view that clips. At rest
            // the clip fell on the edges of the screen and none of that showed.
            // The moment a transition turned the page into an inset card, the
            // clip moved inwards and the rectangle's own three edges, top, left
            // and right, came into view as hard lines across a page they had no
            // business being in.
            //
            // Drawn behind the scroll view and past every edge, the only
            // boundary left is the card's own.
            .containerRelativeFrame(.horizontal) { width, _ in width + PageWash.overshoot * 2 }
    }

    /// The bands laid down the page : the picture's top from nothing up to full
    /// strength and across the bar, its middle where the page begins, and its
    /// foot fading out into the paper.
    private var stops: [Gradient.Stop] {
        let full = PageWash.strength(in: scheme)
        func at(_ distance: CGFloat) -> CGFloat { distance / PageWash.height }

        return [
            Gradient.Stop(color: paint(wash.top, 0), location: 0),
            Gradient.Stop(color: paint(wash.top, full), location: at(PageWash.rise)),
            Gradient.Stop(color: paint(wash.top, full), location: at(PageWash.rise + PageWash.hold)),
            Gradient.Stop(
                color: paint(wash.middle, full * 0.5),
                location: at(PageWash.rise + PageWash.hold + PageWash.fade * 0.45)
            ),
            Gradient.Stop(color: paint(wash.bottom, 0), location: 1),
        ]
    }

    /// One band of the picture, as a page can take it.
    ///
    /// **A photograph's own colours are not a background.** A night shot is
    /// nearly black and a snowfield is nearly white, and either laid behind the
    /// date is a grey page or no colour at all. What is kept is the hue and the
    /// fact that there is one ; how light it is stays the page's own decision,
    /// pale on white and deep on black, moving inside a narrow window so a dark
    /// picture still gives a slightly deeper page than a bright one.
    ///
    /// **And the ceiling is low on paper.** A television studio, which is a
    /// good share of the pictures a news feed carries, is lit in one saturated
    /// colour : taken at its own strength it does not light the page, it paints
    /// it, and the subject pills come out lilac. The ceiling is what keeps a
    /// vivid picture a wash rather than a colour ; the floor below is what
    /// keeps a grey one visible at all.
    ///
    /// **The saturation is lifted, and then given a floor.** A band of a
    /// photograph is already a mean, and a mean is duller than what it
    /// averages : a street scene that anyone would call brownish reads as a
    /// tenth of brown once it has been averaged, and a tenth of brown behind a
    /// dateline is a white page. So what colour there is, is multiplied, and
    /// then held to a minimum a reader can actually see.
    ///
    /// **The floor stops short of nothing.** A picture with no colour in it at
    /// all is a picture with no hue either, only the noise in the last digit of
    /// a mean, and lifting that to a tenth would paint the page whichever way
    /// the noise fell. Under that threshold the wash stays the grey the
    /// photograph is, which is still a warm grey or a cold one and still says
    /// something.
    private func paint(_ tint: Tint, _ alpha: Double) -> Color {
        let (hue, saturation, brightness) = Self.hsb(of: tint)
        let night = scheme == .dark
        let lifted =
            saturation > PageWash.colourless
            ? max(saturation * PageWash.lift, PageWash.floor) : saturation

        return Color(
            hue: hue,
            saturation: min(lifted, night ? 0.75 : 0.34),
            brightness: night ? 0.14 + 0.18 * brightness : 0.80 + 0.12 * brightness,
            opacity: alpha
        )
    }

    /// A colour by its hue, its saturation and its brightness.
    ///
    /// Worked out here rather than asked of `Color`, which answers no questions
    /// about itself. The three channels are what a picture is read as, and the
    /// hue is the one of the three that is worth keeping whole.
    private static func hsb(of tint: Tint) -> (hue: Double, saturation: Double, brightness: Double) {
        let high = max(tint.red, tint.green, tint.blue)
        let low = min(tint.red, tint.green, tint.blue)
        let span = high - low
        guard span > 0 else { return (0, 0, high) }

        let sixth =
            if high == tint.red {
                (tint.green - tint.blue) / span
            } else if high == tint.green {
                2 + (tint.blue - tint.red) / span
            } else {
                4 + (tint.red - tint.green) / span
            }

        var hue = sixth / 6
        if hue < 0 { hue += 1 }

        return (hue, span / high, high)
    }
}
