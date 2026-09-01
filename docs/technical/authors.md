# Authors

A feed that names who wrote an article hands over a byline : a piece of text in a field. Flong shows those bylines as a page of their own, lets the reader single out the ones they follow, and does nothing else with them. This page is about what an author is taken to be, what is cleaned off a byline before it becomes one, and what follows from both.

## An author is a name, not a person

There is no row for a writer and there could not be one. What arrives is `Jean Dupont`, or `J. Dupont`, or `JP Dupont`, or `Jean Dupont et Marie Curie`, and only a human eye can tell which of those are the same person. So **the name is the identity, matched exactly**, and Flong never guesses.

That is the rule the import already follows : what cannot be understood is not invented. A grouping that decided `J. Dupont` was `Jean Dupont` would be right often and wrong quietly, and the reader would have no way of seeing which. Two spellings are two authors, and a reader who wants them as one has the search field on the authors page.

**A byline is not split, either.** A field carrying `Smith, John` and one carrying `Jean Dupont, Marie Curie` are the same string as far as any rule could tell, and cutting on the comma would file half the writers of the world under their own surnames.

## What is cleaned is the spelling, never the person

A byline does not arrive as a name. It arrives wrapped in whatever the format, the publisher and the typesetter put round it, and every one of those wrappings would otherwise be part of the writer's identity : `lawyer@boyer.net (Lawyer Boyer)` would be one person, `By Lawyer Boyer` a second and `Lawyer Boyer | Le Monde` a third, and none of the three would ever meet.

`Author.name(from:)` applies four rules, in order, and every one of them is mechanical :

| Rule | Why it is safe |
| ---- | -------------- |
| Decode entities, collapse whitespace | `Jean&nbsp;Dupont` and a name on its own line inside a pretty-printed element are one writer badly typeset |
| Take the person out of an address : `lawyer@boyer.net (Lawyer Boyer)`, `Lawyer Boyer <lawyer@boyer.net>` | **RSS 2.0 defines its `author` element as the author's e-mail address**, and naming them in brackets after it is the convention its own example uses |
| Drop the leading `By`, `Par`, `Written by`, `Posted by`, `Author:`, `Auteur :` | The publisher's furniture, never part of anybody's name. The word has to be the whole word : `Byron` and `Parker` are left alone |
| Drop what follows a vertical bar | `Jean Dupont \| Le Monde` is a byline with a masthead stapled to it, and keeping it gives one writer a row per paper they write for |

**A dash is left alone**, though `Jean Dupont - BBC News` is the same shape. A bar cannot be part of a name and a dash can, so cutting on it would be guessing where a name ends. The bar is the only separator here that is never anything else.

**Capitalization is left alone.** `JEAN DUPONT` and `Jean Dupont` are two spellings of one person, which is a merge and not a cleaning : deciding they are the same is a judgement, and the initials, the acronyms and the names that really are set in capitals are what a rule would get wrong.

**A newsroom is left alone.** `Rédaction`, `Editor` and `admin` are what the publisher said. Deciding they are not people is a judgement about the byline rather than a fact about its spelling.

**Nobody is nobody.** An empty field, a lone piece of punctuation, an inbox with no name on it and a link are all things a feed puts in that field, and none of them is somebody. They yield no author at all, which is the truth about that article : it is signed by nobody this can name.

### Where the cleaning happens

Once, on the way in, through the single entry point every path goes through : `Entry.init` for a new article and the update in `FeedRefresh` for one that changed, which covers ingestion from a feed and from another device's stream blocks alike. The v24 and v25 migrations put the bylines already stored through the same rule, so the corpus is clean before anything ever groups it.

**It is deliberately deterministic, and that is not a stylistic preference.** The stored byline is the identity a favourite is named after between devices (`author-<digest>`), and articles travel carrying their `author` field. A rule that answered differently on two devices - because one of them can run a model and the other cannot, or because a model changed with an OS update - would give one writer two rows and a favourite that only half travels. Nothing in this pipeline asks the system model, and nothing in it depends on what a device can do.

### The parser prefers a name to an address

RSS 2.0's `author` is an address ; Dublin Core's `dc:creator` and Atom's `<author><name>` are names. Feeds routinely carry both, and which one the parser met last is no reason to prefer it, so `XMLFeedParser` lets the address answer only where nothing has named anybody. All three now go through `HTMLSanitizer.plainText`, which the Atom name used not to.

## The column is clean, so the questions are exact

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
