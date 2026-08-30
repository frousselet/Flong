# Full-text extraction

Most feeds serve a standfirst and a link. The reader gets two sentences and a trip to a browser, which is the one thing a feed reader exists to spare them.

The article is at the end of that link. Flong goes and gets it, once, and keeps it beside what the feed sent.

## When it happens

**What the reader last chose.** An article opens on what its feed sent until the reader asks for the whole one, and asking is also saying so for next time : somebody who wants whole articles is not making a remark about one article. The choice is kept in the iCloud key-value store, so it follows them to their other devices — not in CloudKit, whose three-thousand-record budget is spent on subscriptions, kept articles and read states, and has no business holding a preference.

Once they have chosen the whole article, opening one fetches it : that is no longer speculation, it is what they asked for. Until then nothing is fetched, since a page asked for on opening is a request made to a publisher for something nobody is going to look at.

**Only for an article the reader asked to see whole.** Never a whole feed, never ahead of time, never in a batch. A reader who does not open an article costs its publisher nothing, and a page fetched because somebody is reading it is a page fetched for the reason pages exist. Section 20 asks for politeness to publishers, and speculatively extracting five hundred articles a day is the opposite of it.

**Only when the feed was short.** Under twelve hundred characters of text, what the feed sent is a summary : a standfirst and a first paragraph run to a few hundred, an article runs to thousands. A feed that serves the whole thing has already done the work, and asking its server again would be asking for something already in hand.

**Only once.** What comes back is stored in `entry_body.extracted_html`, so a request buys the article for as long as the article lives, however often it is read.

It goes through the same `FeedFetcher` as everything else : the identifying user agent, the token bucket for that host, the size and time caps. The cap is smaller here, four megabytes, since a page is text.

## Finding the article in the page

The page's own markup first : an `<article>`, an `itemprop="articleBody"`, a `role="main"`, a `<main>`. A publisher who says where the article is has said it better than any heuristic could guess. Where several are found, the one holding the most prose, since a page may carry an `<article>` per item in a list of related pieces.

Failing that, the block whose paragraphs hold the most text that is not links. Each paragraph scores its own length, with a bonus for commas, and hands that score to its parent and half of it to its grandparent : an article is not one long paragraph but a container full of them, and the container is what has to be found.

**Link density is what separates prose from a page of headlines.** A menu is short lines that are all links ; a sidebar is a list of headlines ; an article is prose with the occasional link in it. Above half the text being inside links, a block is not the article, whatever it scored.

## What is left out

Navigation, asides, mastheads, footers, forms, share bars, related-article lists, comments. Judged three ways : by the element's kind (`nav`, `aside`, `form`), by what the publisher called it in a `class` or an `id`, and by link density.

The names are matched **as whole words**, which matters more than it looks : `share` must not take `shareholders`, and an article about a company is full of those.

## What is refused

Under four hundred characters of prose, what was found is not an article. A page answering with two hundred has given a teaser, a consent wall or an error, and the feed's own summary is better than any of those. Nothing is stored, and the reader keeps what the feed sent.

Paywalls are out of scope, as section 19 of the specification says. A wall is refused rather than worked around.

## What the reader sees

What the feed sent, and a menu entry for the whole article. An extraction is a guess about somebody else's markup, and a guess made before anybody asked for it is a guess imposed on them.

While the page is being fetched the feed's version stays on screen, with one line saying what is happening : it is not a wait, it is the reason the text is about to get longer, which a reader would otherwise watch happen without explanation.

## What is kept

**The plain text is rewritten with the extraction.** The plain text is what the full-text index and Spotlight read, and leaving it as the feed's two-line summary would mean fetching the whole article and then searching the teaser. There is no frozen copy to keep in step any more : there is one article, and what the page gave is what everything sees.

## Reading the bytes

A page states its encoding twice, in the `Content-Type` header and in a `<meta>` near the top, and either may be wrong or missing. French pages in particular are still served as Latin-1 by servers configured in the nineties, and reading those as UTF-8 turns every accent into a question mark.

The header first, since it is what the server means today ; the `<meta>` next, since it is what the page was written as ; UTF-8 after that ; Latin-1 last, which decodes any bytes at all and so can never fail. A page read slightly wrong is better than no page.

The list of honoured encodings is short on purpose, and every entry is the encoding it says it is. `iso-8859-15` is not on it : Foundation has no Latin-9, and mapping it to a neighbour would decode French as Central European, which is worse than falling through to the attempts below.

## When the page gives nothing

A page that answers with a teaser is usually a page that did not recognize the reader as a subscriber. **Signing in is offered in the article's own menu**, always, rather than four screens away in the settings and rather than behind a failure the reader has to trigger first : a reader knows they subscribe to a paper long before Flong finds out.

That menu is one item and holds everything. Every action put in a toolbar separately is one the system may fold into an overflow of its own, and an action inside an overflow inside a menu is an action nobody finds. That is not hypothetical : it is what happened, and the reader who asked for the feature could not find it.

`docs/technical/credentials.md` records what a session is and what it is not.
