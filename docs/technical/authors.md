# Authors

A feed that names who wrote an article hands over a byline : a piece of text in a field. Flong shows those bylines as a page of their own, lets the reader single out the ones they follow, and does nothing else with them. This page is about what an author is taken to be, and about the two things that follow from that.

## An author is a name, not a person

There is no row for a writer and there could not be one. What arrives is `Jean Dupont`, or `J. Dupont`, or `Jean Dupont et Marie Curie`, or `By Jean Dupont`, and only a human eye can tell which of those are the same person. So **the name is the identity, matched exactly**, and Flong never guesses.

That is the rule the import already follows : what cannot be understood is not invented. A grouping that decided `J. Dupont` was `Jean Dupont` would be right often and wrong quietly, and the reader would have no way of seeing which. Two spellings are two authors, and a reader who wants them as one has the search field on the authors page.

**A byline is not split, either.** A field carrying `Smith, John` and one carrying `Jean Dupont, Marie Curie` are the same string as far as any rule could tell, and cutting on the comma would file half the writers of the world under their own surnames.

**What is normalized is the spelling, not the person.** A pretty-printed feed hands over

```xml
<author>
  Jean
  Dupont
</author>
```

and that is not a second writer, it is one badly typeset. The name is trimmed and its inner runs of whitespace collapsed, once, in `Author.name(from:)`, which every path into the store goes through : `Entry.init` for a new article and the update in `FeedRefresh` for one that changed. The v24 migration puts the bylines already stored through the same rule, so the corpus is normalized before anything ever groups it.

Because the column is clean, every later question is an exact comparison : `GROUP BY author` for the list, `author = ?` for one writer's page, `author IN (SELECT name FROM favourite_author)` for the favourites. The v24 index on `entry.author` is what keeps the first of those cheap over a corpus of a hundred thousand articles.

## The list is not stored

`AuthorStore.all()` groups the articles. Nothing keeps a table of writers in step, nothing goes stale when a source is removed, and a writer whose last article was purged simply stops being one - exactly as the starred articles are a question the articles answer and not a list kept anywhere.

The one exception is a **favourite with nothing to their name**, which is listed with a count of nothing. It is the ordinary case and not an edge one : a favourite reaching this device from another one arrives before the articles do, and a purge takes the last article of a writer the reader singled out. The decision is the reader's, and it does not disappear because the stream moved under it.

## The favourite

`favourite_author` holds one row per writer the reader singled out, and only for those. A table of every byline there is would be a second copy of what the articles already say, and the first spelling change from a publisher would leave a row standing for nobody.

**It stars nothing.** Section 13 of the specification keeps the star a judgement about one article ; this is a judgement about who wrote it, exactly as a favourite source is one about who printed it. The three sit side by side on the collections page so that they are read as three.

**It is the only one of the three that crosses publishers.** A reader follows a writer through whatever paper they turn up in, which no subscription can express : a favourite source is one address, and a byline is a person moving between them.

### Between devices

One record per favourite, of type `FavouriteAuthor`, named `author-<digest of the name>`. Two devices singling out the same person compute the same name and write one record between them.

**The presence of the record is the whole of the answer**, so un-favouriting deletes it rather than rewriting a field, and the `no` travels as surely as the `yes`. That is the same reasoning marks follow, and the opposite of the read-state blocks, which are merged as a union because reading never unhappens. `docs/technical/sync.md` carries the argument.

A favourite that arrives naming a writer this device has never read is kept all the same. It is a decision ; the articles that answer to it turn up whenever they turn up.

## The two squares

| Square | What it holds | What the number under it counts |
| ------ | ------------- | ------------------------------- |
| **Authors** | Every byline this device has read, plus the favourites nothing is signed by any more | Names |
| **Favourite authors** | The articles signed by a writer the reader singled out | Articles |

The first is the only square on the collections page that opens on people. Everything else there opens on a list of articles, so `ArticleStore` answers no articles for it on purpose rather than quietly answering the whole stream, and the count under it has to be a count of names : a square saying `1 240 articles` that opened on eighty rows would have told the reader the wrong thing before they touched it.

Neither square is drawn when it holds nothing, which is how every built-in square behaves. A reader whose feeds sign nothing is not shown an empty shelf of authors.

## The two ways in

The star on a row of the authors page, and the article's own overflow menu. The second is where the opinion is actually formed - the reader has just finished the piece - and it is inside that menu rather than beside the star in the bar : the bar holds three items, a fourth would earn an overflow of its own, and `docs/technical/interface.md` records why that is a place nothing may go.
