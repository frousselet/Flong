//
//  Theme.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One colour, written once and read in the two places a colour is needed.
///
/// A palette is argued about in hexadecimal and used in a view and in a
/// stylesheet, which want different things : SwiftUI wants a `Color` and a
/// rendered article wants text. Writing each colour twice is writing each
/// colour twice, and the two spellings stop agreeing the first time one of them
/// is changed.
nonisolated struct Ink: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// - Parameter hex: the colour as it is argued about, `0xRRGGBB`.
    /// - Parameter alpha: how much of the page shows through. A hairline is the
    ///   only thing here that wants any : a rule stated as an opaque colour is
    ///   a rule that only looks right on the one paper it was picked against.
    init(_ hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The colour as a stylesheet takes it.
    ///
    /// Channels rather than the hexadecimal it was written as : a colour that
    /// lets the paper through has an alpha, hexadecimal has nowhere to put one,
    /// and a palette that spelled its opaque colours one way and its hairlines
    /// another would be a palette read twice.
    var css: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let channels = "\(byte(red)), \(byte(green)), \(byte(blue))"
        return alpha < 1 ? "rgba(\(channels), \(alpha))" : "rgb(\(channels))"
    }
}

/// What a theme is made of, in one appearance.
///
/// Six colours and no more. Every theme answers all six for light and for dark,
/// which is what stops a palette from being half a palette : a theme that
/// stated only its paper would be a theme that looked right in one appearance
/// and was never tried in the other.
nonisolated struct Palette: Hashable, Sendable {
    /// What the page is printed on.
    let paper: Ink
    /// What it is printed in.
    let ink: Ink
    /// What the application says about the page, rather than what the page says.
    let muted: Ink
    /// The hairline between one thing and the next.
    let rule: Ink
    /// The one colour that is neither paper nor ink : a link, a control, a
    /// thing that can be pressed.
    let accent: Ink
    /// The edge a pill wears, which is a rule that lets the paper through.
    let edge: Ink
    /// A row of a list, which stands very slightly off the paper behind it.
    let surface: Ink
}

/// How the whole application is set : the faces, and the colours.
///
/// **Three, and three is the number.** A list of themes is a list of opinions
/// about what a page is, and past three they stop being opinions and become
/// permutations of a typeface menu. Each of these says something the other two
/// do not, and each says it in the two halves a theme has : what it is set in,
/// and what it is printed on.
///
/// - ``standard`` is the system's own : its colours, its contrast, its accent,
///   and nothing said about any of them.
/// - ``paper`` is the one that looks like something that was printed. Serif
///   headlines on warm paper, and every colour in it pulled back from the
///   contrast a screen defaults to.
/// - ``solarized`` is Ethan Schoonover's palette, which was worked out for
///   reading text for hours and is the reason anybody has heard of it, with
///   headlines set in the monospace face that palette grew up in.
///
/// **A theme speaks in the headline and gets out of the way underneath it.**
/// The standfirst, the body of an article and everything the application says
/// about one are sans in all three : a newspaper sets its headline in the
/// display face it paid for and its columns in whatever reads best down a
/// column, and it has never set both in the same. What is left to a theme is
/// the one line that is glanced at, which is the line a face is for.
///
/// **And two of the three say the same thing there.** ``standard`` and
/// ``paper`` are set in the same faces and are told apart by their colours ;
/// only ``solarized`` changes the headline as well. See ``headline(_:)``.
nonisolated enum Theme: String, CaseIterable, Hashable, Sendable, Identifiable {
    case standard
    case paper
    case solarized

    var id: String { rawValue }

    /// What the reader picks it by.
    var name: LocalizedStringResource {
        switch self {
        case .standard: "Default"
        case .paper: "Paper"
        case .solarized: "Solarized"
        }
    }

    /// The one line under the name, which says what changes.
    ///
    /// A theme is chosen from a list of three words, and three words are not
    /// enough to tell a reader what they are about to get. Each line names the
    /// two halves in the order they will be noticed : the face, then the paper.
    var explanation: LocalizedStringResource {
        switch self {
        case .standard: "Serif headlines, in the colours of the system."
        case .paper: "Serif headlines on warm paper, with the contrast pulled back."
        case .solarized: "Headlines in monospace, on the Solarized palette."
        }
    }

    // MARK: - The faces

    /// Headlines, and the one decision a reader notices first.
    ///
    /// **Two faces for three themes.** ``standard`` and ``paper`` are set the
    /// same and differ in their colours alone ; ``solarized`` is the one that
    /// changes the face as well. That is the right shape rather than a
    /// shortfall : serif headlines are what this application was set in before
    /// there was a choice, for the reason the whole page is set the way it is,
    /// and a reader who asks for warm paper is asking about the paper.
    func headline(_ style: Font.TextStyle) -> Font {
        switch self {
        case .standard, .paper: .system(style, design: .serif, weight: .semibold)
        case .solarized: .system(style, design: .monospaced, weight: .semibold)
        }
    }

    /// The line under a headline : what happened, in one sentence.
    ///
    /// It takes a size because the front page and a story's own page set it at
    /// different ones, and a token that answered only for the smaller of the
    /// two left the larger writing a face of its own at a call site.
    ///
    /// **Sans in all three, whatever the headline is set in.** A theme's
    /// distinctive face is for the line that is glanced at, and prose is not
    /// glanced at : a newspaper sets its headline in the display face it paid
    /// for and its body in the one that is easiest to read down a column, and
    /// it has never set both in the same. So the headline is where a theme
    /// speaks and everything below it is where it gets out of the way.
    func standfirst(_ style: Font.TextStyle = .subheadline) -> Font {
        .system(style, design: .default)
    }

    /// Everything the application says about an article rather than in it :
    /// rooms, counts, times.
    ///
    /// Sans in all three, which is the point of it. The metadata is the
    /// application's own voice, and a theme that set it in the headline's face
    /// would have lost the one distinction the typography is there to make.
    var metadata: Font { .system(.caption, design: .default) }

    // MARK: - The colours

    /// Whether this theme paints the interface itself.
    ///
    /// ``standard`` does not, and it is the only one that does not : it *is*
    /// the system's appearance, and a theme that restated the system's colours
    /// as literals would be a theme that stopped following them the first time
    /// the system changed one, or the reader turned the contrast up, or a
    /// platform drew its windows in something other than white. Its palette
    /// below is stated for the rendered article alone, which is a web page and
    /// has no system colours to inherit.
    var paints: Bool { self != .standard }

    /// The colours, in one appearance.
    func palette(in scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    /// The colour a control takes, or nothing where the system's own is what
    /// is wanted.
    ///
    /// Nothing under ``standard``, for the reason ``paints`` gives. A screen
    /// whose glass sits over a picture nobody chose hands it back too : see
    /// ``Themed``.
    func accent(in scheme: ColorScheme) -> Color? {
        paints ? palette(in: scheme).accent.color : nil
    }

    /// The ground a raised thing sits on : a card, a row of a form, a well.
    ///
    /// The system's own where the theme does not paint, which is what the
    /// standard theme means, and one shade off the theme's paper otherwise. A
    /// card is the one thing a themed page cannot leave to the system : a grey
    /// well is right under the standard theme and plainly foreign on warm paper
    /// or on base03.
    func surface(in scheme: ColorScheme) -> AnyShapeStyle {
        paints ? AnyShapeStyle(palette(in: scheme).surface.color) : AnyShapeStyle(.background.secondary)
    }

    /// The page's own ground, which is what the reader is looking at behind
    /// everything else.
    ///
    /// Asked for by whatever has to disappear into the page rather than stand
    /// on it. The system's own where the theme does not paint, for the reason
    /// ``paints`` gives, and the theme's paper otherwise.
    func paper(in scheme: ColorScheme) -> AnyShapeStyle {
        paints ? AnyShapeStyle(palette(in: scheme).paper.color) : AnyShapeStyle(.background)
    }

    private var light: Palette {
        switch self {
        // The system's own, as the stylesheet has always stated them.
        case .standard:
            Palette(
                paper: Ink(0xFFFFFF),
                ink: Ink(0x1C1C1E),
                muted: Ink(0x6C6C70),
                rule: Ink(0xD8D8DC),
                accent: Ink(0x0B6BCB),
                edge: Ink(0x3C3C43, alpha: 0.15),
                surface: Ink(0xF2F2F7)
            )

        // Warm, and quieter than a screen wants to be. The ink is not black
        // and the paper is not white : a page of text at full contrast is a
        // page that is looked at rather than read, which is the one thing this
        // theme is for.
        //
        // **The accent is dark and barely coloured, rather than cool.** It was
        // a terracotta at half saturation and at the lightness of a
        // photograph, which made the glyphs in the bar read as brown objects
        // rather than as things that can be pressed. The trouble was never the
        // hue : cooling it took the theme apart, the one thing this theme is
        // for being that everything on the page belongs to one warmth. It was
        // the chroma, and the lightness that let the chroma speak. Taken down
        // to where ink lives and to a third of its saturation, the same warmth
        // reads as ink that happens to be warm.
        case .paper:
            Palette(
                paper: Ink(0xF5EFE4),
                ink: Ink(0x33302B),
                muted: Ink(0x7B7368),
                rule: Ink(0xDED4C2),
                accent: Ink(0x5F4533),
                edge: Ink(0x554A3A, alpha: 0.18),
                surface: Ink(0xFBF7EF)
            )

        // Solarized, by its own names : base3 for the paper, base01 for the
        // ink, base00 for what is said about the page, violet for what can be
        // pressed. Not base00 for the ink, which is the palette's body text and
        // sits at four and a half to one against base3 : it passes, barely, and
        // this application has a screen where the contrast has to hold at a
        // caption size.
        //
        // **Violet rather than the blue everybody uses.** The palette has eight
        // accents and the light paper rules out most of them : yellow, green
        // and cyan all sit near three to one against base3, which is a glyph
        // one has to look for, and red, orange and magenta are the colour the
        // live dot already is, or near enough that a row of controls would read
        // as an alarm. Blue is what Solarized itself reaches for and it is the
        // weakest of the four that are left, at 3.4 to one ; violet is 4.1,
        // which is a control one can see, and it is as much Solarized's own as
        // the blue was.
        case .solarized:
            Palette(
                paper: Ink(0xFDF6E3),
                ink: Ink(0x586E75),
                muted: Ink(0x657B83),
                rule: Ink(0x93A1A1, alpha: 0.45),
                accent: Ink(0x6C71C4),
                edge: Ink(0x586E75, alpha: 0.20),
                surface: Ink(0xEEE8D5)
            )
        }
    }

    private var dark: Palette {
        switch self {
        case .standard:
            Palette(
                paper: Ink(0x000000),
                ink: Ink(0xF2F2F7),
                muted: Ink(0x9C9CA1),
                rule: Ink(0x3A3A3C),
                accent: Ink(0x6FB2FF),
                edge: Ink(0x545458, alpha: 0.33),
                surface: Ink(0x1C1C1E)
            )

        // Not black : the paper is warm at night as well, or the theme is a
        // serif face and nothing else once the sun goes down.
        //
        // The accent goes the other way here, since ink on a dark ground is
        // the light thing : the same warmth lifted, and left a little more of
        // its colour than the light one keeps, since a desaturated tone on a
        // dark ground reads as dust. Kept well clear of the cream the page is
        // set in, so a control is still a control and not a slightly different
        // word.
        case .paper:
            Palette(
                paper: Ink(0x181510),
                ink: Ink(0xECE3D3),
                muted: Ink(0x9A9083),
                rule: Ink(0x3A342B),
                accent: Ink(0xB98D70),
                edge: Ink(0xA09480, alpha: 0.28),
                surface: Ink(0x221E17)
            )

        // base03 and base02 for the two grounds, base1 for the ink and base0
        // for what is said about the page : the palette's own dark, in the
        // order it names them.
        //
        // The same violet, lifted. Solarized's whole claim is that its eight
        // accents hold against either ground, and against base03 the violet
        // holds at 3.4 to one, which is the floor rather than a margin. Raised
        // in lightness alone, hue and saturation untouched, it is 5 to one and
        // still recognizably the colour the light page uses.
        case .solarized:
            Palette(
                paper: Ink(0x002B36),
                ink: Ink(0x93A1A1),
                muted: Ink(0x839496),
                rule: Ink(0x586E75, alpha: 0.55),
                accent: Ink(0x8B8FD0),
                edge: Ink(0x93A1A1, alpha: 0.22),
                surface: Ink(0x073642)
            )
        }
    }

    /// The colour of the dot that says a story is still moving.
    ///
    /// One colour for both appearances, where everything else in a theme has
    /// two. It is seven points across and it is the loudest thing on the page
    /// on purpose : a red picked for paper and a red picked for night would be
    /// two shades of alarm nobody could tell apart at that size.
    var live: Color {
        switch self {
        case .standard: .red
        case .paper: Ink(0xB0392E).color
        case .solarized: Ink(0xDC322F).color
        }
    }

    // MARK: - The same decisions, for a page that is not SwiftUI

    /// The face a rendered article's own text is set in.
    ///
    /// The stacks are written out rather than left to `font-family: system-ui`,
    /// which resolves to one face and cannot be asked for the other two.
    /// Sans in all three, for the reason ``standfirst(_:)`` is : a theme's face
    /// is for the headline, and a page of prose set in it is a page that is
    /// looked at rather than read.
    var pageBody: String { Self.sansStack }

    /// The face a rendered article's headline is set in.
    var pageHeadline: String {
        switch self {
        case .standard, .paper: Self.serifStack
        case .solarized: Self.monoStack
        }
    }

    /// The application's own voice inside a rendered article : the byline, a
    /// caption, the dates. Sans in all three, for the reason ``metadata`` is.
    static let sansStack = "-apple-system, system-ui, sans-serif"
    static let serifStack = "ui-serif, \"New York\", Georgia, serif"
    static let monoStack = "ui-monospace, SFMono-Regular, Menlo, monospace"
}

nonisolated extension EnvironmentValues {
    /// How the application is set, for every screen that sets anything.
    ///
    /// In the environment rather than read off the model by each view : a sheet
    /// inherits it, a preview can state one, and a screen that needs a face has
    /// no business knowing there is a model.
    @Entry var theme: Theme = .standard
}

/// Paints a view in the reader's theme.
///
/// **Applied at the root of the window, and again at the root of every sheet.**
/// A sheet inherits the environment and therefore knows which theme it is in,
/// but it is a surface of its own : the system draws it its own colour, and a
/// background painted on the window behind it stays on the window behind it.
///
/// It does nothing at all under the standard theme, which is the whole of what
/// that theme means. See ``Theme/paints``.
struct Themed: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.paints {
            let palette = theme.palette(in: scheme)

            content
                // The ink, and everything the hierarchy derives from it : a
                // view asking for `.secondary` is asking for less of whatever
                // the ink is, so the whole application follows from this one
                // line without a screen having heard of a palette.
                .foregroundStyle(palette.ink.color)
                // **A tint stops at the edge of a photograph.** Glass adapts
                // what it draws to whatever is behind it ; a tint is an
                // instruction, and an instruction overrides the adaptation. A
                // warm brown cross over a red photograph is a control the
                // reader cannot find. So a screen whose glass sits over a
                // picture nobody chose hands the tint back to the system with
                // ``Theme/accent(in:)``. The article's page did that while a
                // photograph ran under its controls ; it has none now, and the
                // rule is here for the next screen that puts glass over one.
                .tint(palette.accent.color)
                // A list draws the system's grouped background, and a themed
                // page with a grey trough down the middle of it is a page in
                // two themes. What the rows themselves stand on is
                // ``SwiftUICore/View/themedRows()``, said on the list itself.
                .scrollContentBackground(.hidden)
                .background(palette.paper.color.ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Stands the rows of a list on the theme's own ground.
///
/// **Said on the list and not with the rest of the painting.** A row's ground
/// is the one thing in a form that the page around it cannot state on its
/// behalf : it has to be declared where the rows are, or the system's white
/// card stands unchanged on warm paper, which is the brightest thing on the
/// screen and the only thing in the panel that is not in the theme.
struct ThemedRows: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.paints {
            content.listRowBackground(theme.palette(in: scheme).surface.color)
        } else {
            content
        }
    }
}

extension View {
    /// Paints this view in the theme the environment carries.
    func themed() -> some View {
        modifier(Themed())
    }

    /// Stands this list's rows on the theme's own ground.
    func themedRows() -> some View {
        modifier(ThemedRows())
    }
}
