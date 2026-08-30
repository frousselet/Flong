# Search

Two things make search work : an index that holds every article, and a language that says what to look for. Both are here ; the semantic search of section 11 is over the marked articles only and arrives with M2.

## The index

A contentless FTS5 table over four columns, `title`, `excerpt`, `body` and `author`, kept in step by triggers on the articles and on their bodies. It holds an index and not a second copy of the articles, and a row can be removed on its identifier alone. `docs/technical/ingestion.md` covers what writes into it ; nothing has to remember to maintain it.

`porter` wraps `unicode61 remove_diacritics 2`, so `reforme` finds `réforme` and `calendrier` finds `calendriers`. Prefix indexes of two and three characters make a search answer while it is still being typed.

The index is disposable : it holds nothing the articles do not, so `SearchIndex.rebuild()` throws it away and writes it again, which is what section 11 asks to be possible at any time.

## The language

An explicit grammar, parsed into a tree, and the tree is what compiles. Nothing is ever built by pasting the reader's words into a statement.

```
query       = disjunction
disjunction = conjunction (OR conjunction)*
conjunction = unary (AND? unary)*
unary       = ("-" | "NOT") unary | primary
primary     = "(" query ")" | field ":" value | value
value       = word | phrase
```

Words next to each other are joined by an implicit `AND`, which is what everyone expects of a search field.

| Category | Operators |
| -------- | --------- |
| fields | `title:`, `text:`, `author:`, `feed:`, `site:`, `tag:`, `lang:` |
| states | `is:unread`, `is:read`, `is:starred`, `is:collected`, `is:annotated`, `has:media`, `has:fulltext` |
| time | `after:2026-01`, `before:2026-08-25`, `age:<7d`, `age:>2w` |
| logic | `AND`, `OR`, `NOT`, brackets, `"a phrase"`, `-` or `!` to exclude, `*` to match a prefix |

`tag:` also matches the folder a feed is filed under, since a folder is a view over a root tag.

**The parser never fails.** A bracket that closes nothing, an `OR` with nothing after it, a field name with no value, an unterminated quote : each has a reading that keeps the rest of the query working. A search field that refuses to search is worse than one that searches for something slightly different from what was meant, and refusing the whole query would leave the reader with neither results nor an explanation.

**The syntax of FreshRSS keeps working.** `intitle:`, `intext:`, `inurl:`, `label:` and `is:favorite` are translated before parsing, so a search carried over from another reader does not quietly return nothing. A word that merely looks like an operator, `intitles`, is left alone.

## Compiling

The tree becomes one SQL condition over the article and its feed.

- **A subtree the index can answer whole becomes one `MATCH`**, however deep it is. Everything else is taken apart into SQL. A negation is never handed to the index : FTS5 only knows `NOT` as a binary operator, and rewriting a unary one into it is how a query starts meaning something else.
- **When the whole query is answered by the index, results are ranked** by `bm25` with the title weighted ten, the standfirst four, the author three and the body one : a reader searching for something wants the article about it before the one that mentions it. A query the index cannot answer whole is ordered by date, which is the honest fallback.
- `feed:`, `site:`, `tag:` and `lang:` are not indexed columns and are matched in SQL, with the reader's own `%` and `_` escaped so they stay text.

## Nothing typed is ever run

Two rules, and the tests that hold them :

1. **Every value travels as a bound parameter.** No value the reader typed reaches a statement as text.
2. **Every word handed to the index is quoted first**, with internal quotes doubled. A reader typing `NEAR(`, `^` or `"` searches for it rather than instructing the index with it. The only operators in a `MATCH` expression are the ones the grammar put there.

## What it costs

Section 11 sets the targets and section 22 asks for them to be measured against a synthetic corpus of 125 000 articles. `SearchPerformanceTests` builds one and holds the store to them. Measured on an Apple silicon Mac :

| Operation | Target | Measured |
| --------- | ------ | -------- |
| a word matching one article in twenty | under 100 ms | 39 ms |
| a word in titles only | under 100 ms | 7 ms |
| a phrase | under 100 ms | 3 ms |
| indexing one article at ingestion | under 10 ms | 0.24 ms |
| a full rebuild of the index | under 2 min | 5 s |

The corpus has to be shaped like a real one, not merely be large. A vocabulary of thirty words repeated everywhere would put every word in every article, and a query for one of them would match all 125 000 : that measures how fast a full scan ranks, which is not what anybody searches for. Words follow the usual lopsided distribution, and the searched terms are planted at known rates.

The suite is opt in, since building the corpus takes half a minute : tick `FLONG_PERFORMANCE` in the scheme's environment, or set `isEnabled="YES"` on it in `Flong.xcscheme`. Nobody should wait for this to find out that a parser test broke.

The suites feed the parser unterminated quotes, stray brackets, lone operators, control characters, two thousand `OR` branches and `'; DROP TABLE entry; --`, and require an answer and an intact store every time.
