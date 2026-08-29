# The interface

Flong is meant to be a tool for watching a subject, not another aggregator. An aggregator is a list of what arrived ; a tool for watching says what is happening, who is saying it, and whether it is still moving. The interface exists to make that difference visible, and every decision below follows from it.

## One column

The three-pane layout is what every reader ships, and it is a poor fit for reading. Two columns of chrome around an article are two columns of not reading, and on iPhone the third pane never existed anyway. Flong shows one thing at a time : the digest, then a story, then an article, each pushed onto a stack, each with its own way back.

Sections keep their own stack, so leaving the library in the middle of something and coming back lands where the reader was, not at the beginning of everything.

## Set like a page, not like a control panel

Boxes are what an interface reaches for when it does not trust its own typography. A card has a border, a fill, a shadow and a corner radius, and all four exist to say *this is a thing* : type already says that, with a rule and some air.

So the digest is set as an editor would set a page :

| Token | Value | Why |
| ----- | ----- | --- |
| `measure` | 680 pt | The column stops there whatever the window does. A line of text past about 80 characters is a line the eye loses. |
| `rhythm` / `tightRhythm` | 28 / 10 pt | Two spacings, used everywhere, so the page has a pulse rather than forty arbitrary gaps. |
| `headline` | system serif, semibold | Serif for what was written, sans for what the application says about it. The two voices stay apart without a single line of chrome. |
| `metadata` | caption, tertiary | The facts under a story are for the reader who asks, not for the one who scans. |

They live in `Flong/Support/Editorial.swift`. A screen that needs a fifth spacing value is a screen that has gone wrong.

Section headers are uppercase, kerned, secondary, and a hairline rule sits above each row. That is the whole vocabulary. No card, no box, no shadow, no glass in the content.

## Liquid Glass belongs to the navigation layer

Apple's guidance for the 2026 material is explicit : glass is the layer that floats **over** the content, and glass must never sit on glass. Both halves matter, and the second one is easy to break by accident.

Flong broke it once. A hand-rolled floating bar in `safeAreaBar(edge: .bottom)`, drawn with `glassEffect`, collided on iPhone with the system search field, which is also glass : two blurred capsules overlapping, each refracting the other. The fix was not to tune the material but to delete the bar. The sections are a system `TabView`, the search tab carries `role: .search` so the system puts search where the system puts search, and `tabBarMinimizeBehavior(.onScrollDown)` gets the bar out of the way when the reader scrolls into something.

The result is that the application contains **no** `glassEffect` call of its own. The only glass on screen is the system's, in the layer it belongs to.

On macOS the same five sections become a sidebar, through `tabViewStyle(.sidebarAdaptable)` : there is no bar to minimize on a Mac, and a window is already out of its own way.

## Motion that says something

Motion is either information or decoration, and decoration on a screen read every morning becomes noise by the second week. Three movements survive :

- **A story page grows out of the row that opened it**, through `navigationTransition(.zoom(sourceID:in:))` and `matchedTransitionSource`. The motion says where the page came from, which is the one thing a push animation cannot. iOS and iPadOS only : macOS has no such transition and needs none.
- **The rule under the period slides** from `Day` to `Week` rather than blinking on, through `matchedGeometryEffect`. It is the same object moving, so it moves.
- **The live dot breathes**, and stops breathing under Reduce Motion, where it becomes a plain dot that still reads as red.

Nothing else animates.

## The period is type, not a control

A segmented picker across the measure is a grey slab speaking a different language from everything under it, and on iPad it put a second capsule directly below the floating tab bar. Three words, in the same kerned uppercase as the section headers, with an accent rule under the one in force, say exactly as much and belong to the page.

## What the model wrote, and how to refuse it

A story's name and its one line are written on the device by the system model. The row says so, with a mark, and the story page explains in one sentence what was done and offers to fall back on the article's own headline. Section 14 of the specification requires the first ; the second is what makes the first honest, since a label the reader cannot act on is decoration.

Where there is no model, or where it refuses, the story is named after its most central article. The page is entire either way.

## What 2026 asked for, and what was ignored

The year's design writing converges on cognitive clarity over sensory richness : calm surfaces, fewer simultaneous signals, motion used as information, artificial intelligence made visible, optional and explainable rather than ambient. That is the page above, and it is also why the digest states its evidence out loud : four rooms, five articles, this shape of arrival, seventeen minutes ago. A story that cannot say why it is on the page does not deserve to be.

What the same writing recommends and Flong does not do : ambient gradients behind content, a bento grid of unequal cards, an assistant panel, and depth for its own sake. They are all ways of adding sensory richness to a screen whose whole job is to be read.

## Accessibility

Dynamic Type carries the layout : the measure is a maximum, not a fixed width, and every row grows. Icon-only controls carry a label. The facts line is combined into one accessibility element per story rather than read as six fragments. The live dot never conveys its meaning by motion or colour alone, since the section header next to it says the same thing in words.
