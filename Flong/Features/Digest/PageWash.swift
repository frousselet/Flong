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

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var wash: Wash?

    var body: some View {
        Group {
            if !theme.paints, contrast != .increased, let wash {
                LinearGradient(stops: stops(of: wash), startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.hold + Self.fade)
                    // The width of the window rather than of the column : the
                    // page holds its type to a measure, and light is not held
                    // to anything.
                    .containerRelativeFrame(.horizontal)
                    // Up under the bar. The wash is laid at the top of the
                    // page's own content, which begins below the bar : left
                    // there, it would draw a hard edge across the screen at
                    // exactly the height a fade exists to make invisible.
                    .offset(y: -Self.hold)
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

    /// How far above the page's own top the colour reaches, at full strength.
    ///
    /// The page begins under the bar, and the bar is where the colour is most
    /// wanted : a date, a large title and four glass buttons over the system's
    /// white is the one part of the screen a photograph can warm without
    /// touching a word of the page itself. This is more than the tallest bar
    /// any of the three platforms draws, so what is above the content is at
    /// full strength whatever the window is doing and the fade begins where the
    /// reader's own page begins.
    private static let hold: CGFloat = 260

    /// How far into the page the colour lasts.
    ///
    /// On the front page, about the subjects, the first heading and the top of
    /// the lead's picture : it is gone by the time that picture arrives, which
    /// is the point, a wash still going at the photograph being a tinted
    /// photograph rather than a lit page. On a story's page the photograph is
    /// at the top and the same distance carries the colour down beside it,
    /// running out around its foot, which is the same idea from the other end :
    /// the light comes off the picture and stops where the picture does.
    private static let fade: CGFloat = 380

    /// How much of the colour the paper takes at the top.
    ///
    /// **Measured against real pages rather than picked.** Half of it was
    /// invisible : the front page led that morning on a photograph of grey
    /// asphalt, which is what a great many news photographs are, and half of
    /// nearly nothing is nothing. A wash a reader cannot see is a wash that is
    /// not there.
    private static func strength(in scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.80 : 0.68
    }

    /// How much the saturation of a band is lifted, the least it may come out
    /// at, and how little of it there has to be for lifting it to be a lie.
    /// See ``paint(_:_:)``.
    private static let lift: Double = 2.2
    private static let floor: Double = 0.10
    private static let colourless: Double = 0.03

    /// The bands laid down the page : the picture's top at the top of it, its
    /// middle where the page begins, and its foot fading out into the paper.
    private func stops(of wash: Wash) -> [Gradient.Stop] {
        let total = Self.hold + Self.fade
        let full = Self.strength(in: scheme)

        return [
            Gradient.Stop(color: paint(wash.top, full), location: 0),
            Gradient.Stop(color: paint(wash.top, full), location: Self.hold / total),
            Gradient.Stop(color: paint(wash.middle, full * 0.5), location: (Self.hold + Self.fade * 0.45) / total),
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
        let lifted = saturation > Self.colourless ? max(saturation * Self.lift, Self.floor) : saturation

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
