# Reading and sanitizing HTML

Feed content is HTML written by a thousand different generators, and it is almost never well formed. Flong parses it itself, with no external library, because three parts of the application need the same thing : the sanitizer of section 10, feed discovery, and the h-feed parser.

## The parser

`HTMLTokenizer` and `HTMLDocument` implement the shape of the HTML5 algorithms, not their letter. There is no failure mode : anything that cannot be understood comes back as text, because losing an article to a malformed tag would be the worse outcome.

What it handles, since real feeds contain all of it :

- unquoted, single quoted and valueless attributes, in any case ;
- a stray `<` that opens nothing, which stays text ;
- an element left open, closed by its parent ;
- an end tag that closes nothing, dropped ;
- elements that cannot nest closing each other, so `<li>One<li>Two` is two items rather than one inside the other ;
- raw text elements, where a `<` inside a script is not a tag. Treating it as one is how a sanitizer lets one through.

Character references are decoded into the tree and escaped again on the way out. The full HTML table runs past two thousand names ; the hundred that turn up in feeds are known, and a name that is not is left as it stands rather than guessed at.

## The whitelist

An element that is not on the list does not survive, and neither does an attribute. A whitelist is the only policy that stays safe as the web invents new ways to run code : anything new is unknown, and unknown is refused.

| Kind | Treatment |
| ---- | --------- |
| Text, headings, lists, tables, images, media, links | kept, with the attributes listed in `HTMLSanitizer` |
| `script`, `style`, `iframe`, `object`, `embed`, `svg`, `form` and its fields | dropped **with their content** |
| Anything else unknown, `font` or a custom element | unwrapped : the element goes, its text stays |
| `class`, `id`, `style`, `on*` | dropped, since none of them are on the list |

`lang` and `dir` are the only attributes any element may keep, because they carry meaning for a screen reader.

## Three particular treatments

**Addresses are checked, not trusted.** Every `href`, `src`, `cite` and `poster` is resolved against the article address, so the relative links a feed serves still work, and kept only when it ends up as `http`, `https` or `mailto`. A `javascript:` link is not a link ; the element is unwrapped and its text stays.

**Links hand nothing to where they go.** `rel="noopener noreferrer"` is forced on every link that survives.

**Tracking pixels are dropped.** An image whose width or height is zero or one is there to count readers, not to be seen. Opening an article should not tell the publisher who read it and when, and with no server of its own Flong cannot proxy the request away.

## Plain text

`HTMLSanitizer.plainText` flattens an article, turning block elements and `<br>` into line breaks and collapsing the runs of whitespace that markup leaves behind. It feeds the excerpt today, and the full-text index at M1.
