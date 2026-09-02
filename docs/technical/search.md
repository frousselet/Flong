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

`tag:` matches a tag and everything under it, so `tag:collection` answers for every collection the reader made. It used to match the folder a feed was filed under as well, since a folder was a view over a root tag ; there are no folders, and a source belongs to the publisher serving it rather than to a filing, so `feed:` and `site:` are what narrow a search to where an article came from.

**The parser never fails.** A bracket that closes nothing, an `OR` with nothing after it, a field name with no value, an unterminated quote : each has a reading that keeps the rest of the query working. A search field that refuses to search is worse than one that searches for something slightly different from what was meant, and refusing the whole query would leave the reader with neither results nor an explanation.

**The syntax of FreshRSS keeps working.** `intitle:`, `intext:`, `inurl:`, `label:` and `is:favorite` are translated before parsing, so a search carried over from another reader does not quietly return nothing. A word that merely looks like an operator, `intitles`, is left alone.

## What the field offers

**Subjects, never syntax.** `SearchSubjects` reads the headlines of the stories on the digest and hands back what they are about : the longest run of distinctive words in each, where distinctive means the tagger called it somebody or somewhere, or the way it is written says it names something. A capital the sentence did not ask for, a capital inside the word, a digit beside letters, a year. Where that run is a single word the next one joins it, so `Trump donne dix jours à l'Iran` offers `Trump Iran` and `Apple présente l'iPhone 18 Pro` offers `iPhone 18 Pro` rather than `Apple`. French elides, so `l'` and `d'` come off the front of a word while `aujourd'hui` keeps its apostrophe.

It runs on no model at all, which is the point : section 15 says the path without Apple Intelligence always exists and is always tested. `docs/technical/interface.md` sets out the screen : the pills above the keyboard, the searches the reader ran before, and why arriving in the section is what puts the cursor in the field.

## Reading a sentence

`tag:`, `is:unread` and `after:` are what a dynamic collection is described with and what the FreshRSS import understands. They are not what a reader types. `QuestionReader` is what turns one into the other.

**The model says what the sentence names, never what to run.** It answers with five pieces : the words, the publication, the writer, the state and the moment. `QuestionReader` builds the tree from those, so the compiler stays the only thing that ever turns anything into SQL, and a model that emitted `site:lemonde.fr` would be a model writing the thing that compiles.

Three guards, and they matter more than the prompt :

1. **Every word it hands back has to have been typed.** A sentence about Iran comes back as `Iran conflict` about as often as not, and the added word narrows a search the reader never narrowed. Compared term by term, folded, so `l'Iran` still yields `Iran`.
2. **A publication and a writer are matched against what the reader has** : the sources actually followed, by name or by host, and the bylines the feeds actually carried. A name matching nothing goes back into the words, where it is at worst a word they typed, so a model inventing a newspaper costs nothing.
3. **A sentence of fewer than three words is never sent.** `iran` means look for `iran`, and a round trip to a language model to be told so is a second of waiting bought for nothing.

`QuestionReader.plainly(_:in:)` is the path without a model, and it is a good one rather than a fallback. The words that say nothing go, including the handful that are the reader talking about their feed reader rather than about the news : `les articles du Monde sur la rentrée scolaire` is four words of scaffolding and one subject. And a publication is looked up against the sources the reader follows, which is a lookup and not a model : `Monde` becomes `site:lemonde.fr` on any device, which is most of what reading the sentence was for. What is left is joined by `AND`, as words in a search field always have been.

Whatever was understood beyond the words is handed back with the tree, and the interface writes it above the results. A search that narrows itself has to say so, or a reader who sees a third of the articles they expected concludes the search is broken.

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
