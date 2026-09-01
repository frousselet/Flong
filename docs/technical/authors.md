# Authors

A feed that names who wrote an article hands over a byline : a piece of text in a field. Flong shows those bylines as a page of their own, lets the reader single out the ones they follow, and does nothing else with them. This page is about what an author is taken to be, what is cleaned off a byline before it becomes one, and what follows from both.

## An author is a name, not a person

There is no row for a writer and there could not be one. What arrives is `Jean Dupont`, or `J. Dupont`, or `JP Dupont`, or `Jean Dupont et Marie Curie`, and only a human eye can tell which of those are the same person. So **the name is the identity, matched exactly**, and Flong never guesses.

That is the rule the import already follows : what cannot be understood is not invented. A grouping that decided `J. Dupont` was `Jean Dupont` would be right often and wrong quietly, and the reader would have no way of seeing which. Two spellings are two authors, and a reader who wants them as one has the search field on the authors page.

## A byline names more than one person

No feed format gives a publisher a second author element they actually use, so they write the whole newsroom into the one field : `Claire Ancelin et Paul Rey`, `Smith; Doe`, `A & B`. Kept whole, those two people are a third person who has written one article, and neither of the two is ever findable.

`Author.people(in:)` cuts on the separators that are never anything else - a semicolon, an ampersand, and `and` or `et` standing alone between two names, whatever their case. The line is cleaned **before** it is cut, since the wrappings go round the whole of it : `desk@example.com (Claire Ancelin and Paul Rey)` names two people inside one address, and cutting first would leave half an address on one of them. Each name is then put through the cleaner again, which is what takes a masthead off the last of them and a credit off the first.

**A comma is not a separator on its own.** `Dupont, Jean` is one person written the way a directory writes them and `Claire Ancelin, Paul Rey` is two ; what tells them apart is that neither half of the first holds a space. The rule is applied to each piece rather than to the line, so `Dupont, Jean; Curie, Marie` is two people written backwards and not four written wrong.

Everything the comma cannot answer is left alone. `Claire Ancelin, Reporter` is a name and a job, and no rule can tell that from a name and a name.

**The article's own page and the authors list ask the same function.** They did not, and the page had been unpicking bylines into one pill per person since before the authors page existed : two pills over an article that counted as one writer in the list. There is one splitter now, in `Author`, and `ArticleDocument` calls it.

## An article has authors, and the schema said it had one

The `author` column is what the publisher wrote, and it stays : it is what the article is headed with, what the full-text index holds, and what travels between devices in a stream block. Beside it, v26 puts `entry_author` - one row per person per article, with their place in the byline.

That row is what every question about a writer is asked of : the list is `GROUP BY name` over it, one writer's page is `entry_id IN (SELECT ... WHERE name = ?)`, and the favourites square is the same with the name in `favourite_author`. An article two favourites wrote together is one article in that square and not two, which the byline column could not have expressed.

The foreign key is what keeps it honest : an article that goes takes its authors with it, unlike `tag_binding`, which points at one of three tables and can carry no key at all.

**It is written by hand at each path that stores an article**, through `AuthorStore.index(_:byline:in:)` : the two in `FeedRefresh`, one for a new article and one for a byline a publisher rewrote, and the one in `StreamBlock` for an article arriving from another device. A path that forgot would leave its articles out of their own writers' pages and nothing else would notice, so the test for it walks an ingestion end to end rather than trusting the call sites.

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

Because the names are clean and stored one per row, every question about a writer is an exact comparison against an indexed column, over a corpus of a hundred thousand articles.

The index over `entry.author` itself survives, under the name `entry_on_author` since the table took the other one. It answers nothing the interface asks any more ; what it is for is the pass that re-spells every byline when a rule changes, which has happened twice already, and which without it would be a full scan per distinct name.

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

## Where they write, on the row

A byline on its own is a name in a list of a thousand names. The same byline with `Le Monde` and `Libération` after it is somebody the reader can place before they have opened anything, and it is the thing this page is for : a writer moving between papers is what no subscription can express, and two marks say it without a word.

The marks follow the name rather than the number, since they are an attribution and not a property of the row. They are **the publisher and never the desk**, exactly as an article row's stamp is : two feeds of one paper are one mark. They come from the same `publishers` map every other mark in the application is looked up in, so a publisher the reader renames is renamed here at the same moment, and nothing about a picture is stored beside a name.

**Four of them, and no `+3` after.** They are a hint of where somebody writes, not an inventory : the row already carries a number, and a second one counting papers would be two numbers doing different jobs side by side. A reader who wants the whole answer opens the writer. Where there are none - a favourite whose articles have not arrived - the row draws nothing rather than a run of aerials, this being a byline and not a column of marks that has to be kept.

They are ordered by how much of the writer each publisher has, so the paper somebody mostly writes for is the mark that survives the cap, and alphabetically where two are equal so a row does not reshuffle itself between two readings.

Both of those are one walk of the same rows : the count is grouped over the people and the marks over the publishers, which are two groupings of one query rather than two queries.

## The two ways in

The star on a row of the authors page, and the article's own overflow menu. The second is where the opinion is actually formed - the reader has just finished the piece - and it is inside that menu rather than beside the star in the bar : the bar holds three items, a fourth would earn an overflow of its own, and `docs/technical/interface.md` records why that is a place nothing may go.
