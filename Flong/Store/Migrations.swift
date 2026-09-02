//
//  Migrations.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import GRDB

nonisolated extension AppDatabase {
    /// The schema, as an ordered list of migrations.
    ///
    /// A shipped migration is never edited : a schema change is a new
    /// registration, appended after the previous one, because a database in the
    /// field has already run everything above it.
    ///
    /// Identifiers of the store are UUIDv7 and are stored as sixteen byte blobs,
    /// which sort by creation time exactly as the strings would, in less than
    /// half the space.
    ///
    /// The `entry_fts` virtual table of section 6 of the specification is not
    /// here : the full-text index arrives with M1, in its own migration, and
    /// carries the trigger set that keeps it in step with `entry_body`.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
            // A migration edited rather than appended is a mistake. In debug
            // builds it costs a local database ; in the field it would be a
            // corrupted schema.
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1.model") { db in
            try createStream(db)
            try createLibrary(db)
            try createOrganization(db)
            try createSyncState(db)
        }

        migrator.registerMigration("v2.search") { db in
            try createSearchIndex(db)
        }

        migrator.registerMigration("v3.readStates") { db in
            try createReadStateBlocks(db)
        }

        migrator.registerMigration("v4.stories") { db in
            try createStories(db)
        }

        migrator.registerMigration("v5.covers") { db in
            try addCovers(db)
        }

        migrator.registerMigration("v6.topics") { db in
            try addTopics(db)
        }

        migrator.registerMigration("v7.briefLanguage") { db in
            try addBriefLanguage(db)
        }

        migrator.registerMigration("v8.recordTags") { db in
            try createRecordTags(db)
        }

        migrator.registerMigration("v9.askAgain") { db in
            try askAgain(db)
        }

        migrator.registerMigration("v10.topicPreferences") { db in
            try createTopicPreferences(db)
        }

        migrator.registerMigration("v11.severalTopics") { db in
            try createStoryTopics(db)
        }

        migrator.registerMigration("v12.duplicates") { db in
            try addDuplicates(db)
        }

        migrator.registerMigration("v13.keyWhatIsAlreadyHere") { db in
            try keyExistingArticles(db)
        }

        migrator.registerMigration("v14.vocabulary") { db in
            try createVocabulary(db)
        }

        migrator.registerMigration("v15.askedOnce") { db in
            try db.alter(table: "story") { table in
                table.add(column: "topics_asked_at", .datetime)
            }
        }

        // Why a kept article was kept, written on the copy rather than read
        // back off the article it came from.
        //
        // Starring lived on the stream row alone, and a library item points at
        // that row with `ON DELETE SET NULL` : the day retention purges the
        // article, a starred item quietly stops being starred. The library
        // exists precisely so that what was kept survives its source, and a
        // collection of favourites that empties itself on a purge is the
        // clearest possible way to break that promise.
        //
        // Backfilled from the stream while the rows are still there.
        migrator.registerMigration("v16.whyItWasKept") { db in
            try db.alter(table: "library_item") { table in
                table.add(column: "starred_at", .datetime)
            }
            try db.execute(
                sql: """
                    UPDATE library_item SET starred_at = promoted_at
                    WHERE entry_id IN (SELECT id FROM entry WHERE is_starred = 1)
                    """
            )
        }

        // Which archives of another device this one has already read.
        //
        // Local, and deliberately : what this device has taken from a file is
        // nobody else's business, and a ledger that travelled would have every
        // device skip what only one of them had read.
        migrator.registerMigration("v17.archiveLedger") { db in
            try db.create(table: "archive_ingest") { table in
                table.primaryKey("name", .text)
                table.column("modified_at", .datetime).notNull()
                table.column("ingested_at", .datetime).notNull()
            }
        }

        // One notion of an article, and one only.
        //
        // The library was a second store holding a frozen copy of what the
        // reader kept. Every reason it existed for has gone : the stream is
        // never purged now, it synchronizes whole, and it carries its own text.
        // What was left was freezing the version read, which the reader has
        // decided they do not want at the price of two stores.
        //
        // What the copy really held, besides the frozen text, was the reader's
        // own marks : the note, the vector, and through `tag_binding` the
        // collections. Those move onto the article itself.
        //
        // A copy whose article had already been purged has no article to move
        // onto, so one is made from the copy. Losing those would be losing
        // exactly what the library was built to protect, on the one day it is
        // taken away.
        migrator.registerMigration("v18.oneArticle") { db in
            try db.alter(table: "entry") { table in
                table.add(column: "annotation", .text)
                table.add(column: "vector", .blob)
                table.add(column: "vector_model", .text)
                table.add(column: "vector_revision", .text)
            }

            // The orphans first, so that everything below can assume an entry.
            let orphans = try Row.fetchAll(
                db,
                sql: """
                    SELECT l.id AS id, l.feed_url AS feed_url, l.guid AS guid, l.url AS url, l.title AS title,
                           l.author AS author, l.language AS language, l.published_at AS published_at,
                           l.promoted_at AS promoted_at, l.content_html AS content_html,
                           l.plain_text AS plain_text, l.image_url AS image_url
                    FROM library_item l
                    WHERE l.entry_id IS NULL OR l.entry_id NOT IN (SELECT id FROM entry)
                    """
            )
            for row in orphans {
                guard let feedURL = row["feed_url"] as String?,
                    let feedID = try UUID.fetchOne(db, sql: "SELECT id FROM feed WHERE url = ?", arguments: [feedURL])
                else { continue }

                let made = UUID.v7()
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO entry
                        (id, feed_id, guid, url, title, author, language, published_at, received_at,
                         is_read, is_starred, is_hidden, has_media, image_url)
                        VALUES (?,?,?,?,?,?,?,?,?,1,0,0,0,?)
                        """,
                    arguments: [
                        made, feedID, row["guid"] as String, row["url"] as String?, row["title"] as String,
                        row["author"] as String?, row["language"] as String?, row["published_at"] as Date?,
                        row["promoted_at"] as Date, row["image_url"] as String?,
                    ]
                )
                if let html = row["content_html"] as String? {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entry_body (entry_id, sanitized_html, plain_text)
                            VALUES (?,?,?)
                            """,
                        arguments: [made, html, row["plain_text"] as String?]
                    )
                }
                try db.execute(
                    sql: "UPDATE library_item SET entry_id = ? WHERE id = ?",
                    arguments: [made, row["id"] as UUID]
                )
            }

            // The marks, onto the article.
            try db.execute(
                sql: """
                    UPDATE entry SET
                        annotation = (SELECT l.annotation FROM library_item l WHERE l.entry_id = entry.id),
                        vector = (SELECT l.vector FROM library_item l WHERE l.entry_id = entry.id),
                        vector_model = (SELECT l.vector_model FROM library_item l WHERE l.entry_id = entry.id),
                        vector_revision = (SELECT l.vector_revision FROM library_item l WHERE l.entry_id = entry.id),
                        is_starred = CASE
                            WHEN (SELECT l.starred_at FROM library_item l WHERE l.entry_id = entry.id) IS NOT NULL
                            THEN 1 ELSE is_starred END
                    WHERE id IN (SELECT entry_id FROM library_item WHERE entry_id IS NOT NULL)
                    """
            )

            // The collections, onto the article. A binding names what it points
            // at by kind, so the kind changes with the identifier.
            try db.execute(
                sql: """
                    UPDATE OR IGNORE tag_binding SET
                        target_kind = 'entry',
                        target_id = (SELECT l.entry_id FROM library_item l WHERE l.id = tag_binding.target_id)
                    WHERE target_kind = 'library_item'
                      AND target_id IN (SELECT id FROM library_item WHERE entry_id IS NOT NULL)
                    """
            )
            try db.execute(sql: "DELETE FROM tag_binding WHERE target_kind = 'library_item'")

            try db.drop(table: "library_item")
        }

        // A mark that arrives before the article it is about.
        //
        // The whole stream travels between the devices now, so the article is
        // on its way, but CloudKit hands its batches over in whatever order it
        // likes and a star may well land first. Dropping it would lose it for
        // good : nothing re-sends a record that was already delivered. It waits
        // here instead, and is written the moment the article turns up.
        migrator.registerMigration("v19.marksThatArriveFirst") { db in
            try db.create(table: "pending_mark") { table in
                table.column("feed_url", .text).notNull()
                table.column("guid", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("received_at", .datetime).notNull()
                table.primaryKey(["feed_url", "guid"])
            }
        }

        // The pictures a publisher stated over plain `http`.
        //
        // App Transport Security refuses such a request outright, so every one
        // of them is a hole in an article the reader is looking at now, with a
        // `-1022` in the console and nothing on screen to say why. The
        // sanitizer raises them as articles arrive ; this raises the ones
        // already written down, which nothing would ever sanitize again.
        //
        // Only what the view fetches itself. A link stays exactly as the
        // publisher wrote it : it is handed to the browser, which is not bound
        // by this policy.
        migrator.registerMigration("v20.secureThePictures") { db in
            for column in ["sanitized_html", "extracted_html"] {
                for attribute in ["src", "poster"] {
                    try db.execute(
                        sql: """
                            UPDATE entry_body SET \(column) = replace(\(column), ?, ?)
                            WHERE \(column) LIKE ?
                            """,
                        arguments: [
                            "\(attribute)=\"http://", "\(attribute)=\"https://",
                            "%\(attribute)=\"http://%",
                        ]
                    )
                }
            }
        }

        // Three natures of subject, where there had been two.
        //
        // The column said whether the reader wrote it. What is wanted is where
        // it came from : the sections every newspaper has, the ones this reader
        // wrote, and the ones the model came up with for one story. The first
        // of those did not exist and is what the change is for : a page that
        // reads sensibly on its first day rather than after a fortnight of the
        // model naming things.
        //
        // The old column stays and stays true. Reading it is how this is
        // backfilled, and a reader's own subject is still their own.
        // The values are written out rather than taken from `TopicKind`, which
        // no longer has a case for `smart` : a shipped migration describes what
        // a store went through and may not change its meaning because the type
        // above it did.
        migrator.registerMigration("v21.threeKindsOfSubject") { db in
            try db.alter(table: "topic") { table in
                table.add(column: "kind", .text).notNull().defaults(to: "smart")
            }
            try db.execute(sql: "UPDATE topic SET kind = ? WHERE is_own = 1", arguments: ["own"])
        }

        // The model may no longer name a subject.
        //
        // What it had already named is the question this answers. Those names
        // were a drift of near synonyms of the sections that existed anyway, in
        // whichever language the articles happened to be written in, and the
        // catalogue is fifty names deep now rather than thirteen.
        //
        // **A subject the reader spoke about becomes theirs.** They pressed it
        // up or down, so it is a name they had an opinion about, and a
        // preference nobody can find is a preference nobody can undo.
        // Everything else goes.
        //
        // **A filing goes with the subject it names.** `story_topic` has no key
        // on `topic`, so a filing left behind is a pill the reader can see on
        // the front page and cannot find, cannot manage and cannot remove.
        //
        // **And a story left under nothing is asked about again.** It was
        // answered by a vocabulary that no longer exists, so the answer no
        // longer stands ; without this it would keep its stamp and never be
        // filed again, which is the fault `docs/technical/digest.md` records.
        migrator.registerMigration("v22.twoKindsOfSubject") { db in
            try db.execute(
                sql: """
                    UPDATE topic SET kind = 'own', is_own = 1
                    WHERE kind = 'smart' AND name IN (SELECT name FROM topic_preference)
                    """
            )
            try db.execute(
                sql: "DELETE FROM story_topic WHERE name IN (SELECT name FROM topic WHERE kind = 'smart')"
            )
            try db.execute(sql: "DELETE FROM topic WHERE kind = 'smart'")
            try db.execute(
                sql: """
                    UPDATE story SET topics_asked_at = NULL
                    WHERE topics_asked_at IS NOT NULL
                      AND id NOT IN (SELECT story_id FROM story_topic)
                    """
            )

            // The column still defaulted to a value that no longer names
            // anything, which is a trap for whoever next writes raw SQL against
            // this table. SQLite cannot alter a default, so the table is built
            // again ; it holds tens of rows.
            try db.create(table: "topic_rebuilt") { table in
                table.primaryKey("name", .text)
                table.column("is_own", .boolean).notNull().defaults(to: false)
                table.column("created_at", .datetime).notNull()
                table.column("kind", .text).notNull().defaults(to: "standard")
            }
            try db.execute(sql: "INSERT INTO topic_rebuilt SELECT name, is_own, created_at, kind FROM topic")
            try db.drop(table: "topic")
            try db.rename(table: "topic_rebuilt", to: "topic")
        }

        // The folders are gone, and the sources are grouped by publisher.
        //
        // **Nothing in Flong ever let a reader make a folder.** The only ones
        // that existed came out of somebody else's OPML file, so the feature
        // was a tree the reader inherited and could not tend : no screen
        // created one, none renamed one, and the only way to be rid of one was
        // to stop following everything in it. A column carrying somebody
        // else's filing is not organization, it is a leftover.
        //
        // **The grouping that replaced it stores nothing**, which is the
        // point. A group is the address its feeds share, so it is right the
        // moment a subscription lands, it cannot go stale, and there is no
        // empty one to clean up. The one thing that cannot be worked out is
        // what the reader calls it, and that is the whole of `source_name`.
        //
        // A favourite source is the reader singling a publisher out. It is not
        // a starred article and it never makes one : section 13 keeps the star
        // a judgement about an article, and this is a judgement about who
        // wrote it.
        migrator.registerMigration("v23.publishersRatherThanFolders") { db in
            try db.alter(table: "feed") { table in
                table.drop(column: "folder")
                table.add(column: "is_favourite", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "source_name") { table in
                table.primaryKey("id", .blob)
                table.column("domain", .text).notNull().unique()
                table.column("name", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }
        }

        // **The writers, who were in the schema all along and had nowhere to
        // be.** An article has carried its byline since v1 ; nothing ever asked
        // the column a question, so nothing ever needed it grouped or indexed.
        // The authors page asks both.
        //
        // **A byline is normalized once, on the way in**, and the spellings
        // already stored are put through the same rule here. A name wrapped in
        // the whitespace of a pretty-printed feed is not a second writer, and
        // one grouping that answered `Jean Dupont` twice would be a list the
        // reader cannot trust. See ``Author``.
        //
        // **A favourite author is one row, and only for the writers the reader
        // singled out.** A table of every byline there is would be a second
        // copy of what the articles already say, and it would go stale the
        // first time a publisher changed a spelling.
        migrator.registerMigration("v24.theWriters") { db in
            try normalizeBylines(db)

            try db.create(index: "entry_author", on: "entry", columns: ["author"])

            try db.create(table: "favourite_author") { table in
                table.primaryKey("id", .blob)
                table.column("name", .text).notNull().unique()
                table.column("created_at", .datetime).notNull()
            }
        }

        // **The rule for a byline grew, so the column is put through it again.**
        // v24 trimmed a name and collapsed its whitespace, which was the whole
        // of what it did. It left `lawyer@boyer.net (Lawyer Boyer)` standing as
        // a writer, because RSS 2.0 defines its `author` element as an address ;
        // it left `By Jean Dupont` beside `Jean Dupont` as two people ; and it
        // left a masthead stapled to a name, which gives one writer a row per
        // paper they write for. ``Author/name(from:)`` now takes all of that
        // out, and a database that has already run v24 would keep the old
        // spellings for ever without this.
        //
        // **A migration calling into live code is a thing to be careful of**,
        // since what it does then changes under it. It is right here and only
        // because the rule is idempotent : both of these ask the column to be
        // whatever the current rule says, so a fresh database running v24 with
        // today's rule and an old one running v24 then v25 land in the same
        // place, which is the only property that matters.
        migrator.registerMigration("v25.theWholeByline") { db in
            try normalizeBylines(db)
        }

        // **An article has authors, and the schema has said it has one since
        // v1.** No feed format gives a publisher a second author element they
        // actually use, so they write the whole newsroom into the one field :
        // `Claire Ancelin et Paul Rey`, `Smith; Doe`. Grouped on the column,
        // two people are a third person who has written one article, and
        // neither of the two is findable. The article's own page has been
        // unpicking that field into one pill per person all along, so the page
        // and the list disagreed about how many people wrote a piece.
        //
        // **The column stays and holds the byline.** It is what the article is
        // headed with, what the full-text index holds and what travels between
        // devices ; nothing about it changes. What is new is the row per person
        // beside it, which is what every question about a writer is asked of
        // from here on.
        //
        // The foreign key is what keeps it honest : an article that goes takes
        // its authors with it, unlike `tag_binding`, which points at one of
        // three tables and can carry no key at all.
        migrator.registerMigration("v26.everybodyWhoSigned") { db in
            // SQLite keeps tables and indexes in one namespace, and v24 spent
            // this name on the index over the byline. The index is still worth
            // having : it is what makes a pass that re-spells every byline an
            // indexed range rather than a scan per name, and there have been
            // two of those already. So it moves rather than goes, under the
            // name GRDB would have given it.
            try db.execute(sql: "DROP INDEX IF EXISTS entry_author")

            try db.create(table: "entry_author") { table in
                table.column("entry_id", .blob).notNull().references("entry", onDelete: .cascade)
                table.column("name", .text).notNull().indexed()
                // Where they stood in the byline, so a page credits them in the
                // order the publisher wrote them rather than in the order
                // SQLite happens to hold them.
                table.column("position", .integer).notNull()
                table.primaryKey(["entry_id", "name"])
            }

            try db.create(index: "entry_on_author", on: "entry", columns: ["author"], ifNotExists: true)

            // One statement per person per distinct byline rather than one per
            // article : a corpus of a hundred thousand pieces carries a few
            // thousand bylines, and the index just re-made over the column is
            // what makes each of those an indexed range rather than a scan.
            let bylines = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT author FROM entry WHERE author IS NOT NULL AND author <> ''"
            )
            for byline in bylines {
                for (position, person) in Author.people(in: byline).enumerated() {
                    try db.execute(
                        sql: """
                            INSERT OR IGNORE INTO entry_author (entry_id, name, position)
                            SELECT id, ?, ? FROM entry WHERE author = ?
                            """,
                        arguments: [person, position, byline]
                    )
                }
            }
        }

        // A collection the reader shared, or was invited to.
        //
        // **The zone is the row's reason to exist.** A `CKShare` reaches one
        // zone and a zone holds one zone-wide share, so a shared collection is
        // a zone of its own and this is the only thing that remembers which.
        // The name cannot stand in for it : a reader may rename a collection,
        // and two readers may perfectly well name theirs the same thing.
        //
        // **Nothing here is synchronized between the reader's own devices.**
        // The zone and the share are in their private database already, so a
        // second device learns of both from CloudKit rather than from a record
        // this table would have to write. What this holds is the local index
        // back to them.
        migrator.registerMigration("v27.aCollectionShared") { db in
            try db.create(table: "shared_collection") { table in
                table.primaryKey("id", .blob)
                // The zone, which is the identity of the thing. Unique because
                // a zone carries exactly one shared collection.
                table.column("zone_name", .text).notNull().unique()
                // Whose zone it is : the reader's own, or the participant who
                // invited them. `CKCurrentUserDefaultName` for a collection of
                // the reader's making.
                table.column("owner_name", .text).notNull()
                // The made collection this stands for, when it is one of the
                // reader's own. A collection they were invited to has no tag
                // of theirs behind it and carries its name instead.
                table.column("collection_name", .text)
                table.column("title", .text).notNull()
                table.column("is_owned", .boolean).notNull()
                table.column("share_url", .text)
                table.column("created_at", .datetime).notNull()
            }

            // What the collections page asks : is this one shared, and by whom.
            try db.create(
                index: "shared_collection_on_collection",
                on: "shared_collection",
                columns: ["collection_name", "is_owned"]
            )
        }

        // An article somebody else filed into a collection they shared.
        //
        // **A table of its own, and that is not tidiness.** What is here came
        // from a feed the reader does not follow, and every guarantee about
        // their own articles has to go on being true : it is not counted
        // unread, not purged, not indexed as theirs, not swept up by a rule or
        // a replay, and never re-shared. Putting it in `entry` would break all
        // of those at once, and each of them silently.
        //
        // It holds an excerpt and never a body, because a body never crossed.
        migrator.registerMigration("v28.whatSomebodyElseFiled") { db in
            try db.create(table: "shared_entry") { table in
                table.primaryKey("id", .blob)
                table.column("zone_name", .text).notNull()
                // Which participant's list it came in, as the record that
                // carried it is named.
                //
                // **Not the person, because a deletion does not carry one.**
                // A record that arrives says who wrote it ; a record that is
                // deleted arrives as an identifier and nothing else, and the
                // whole point of a list per participant is that one person's
                // removal touches only their own rows. The name is what both
                // events have in common, so the name is what this is keyed by.
                table.column("list_key", .text).notNull()
                // Whoever put it there, as CloudKit names them, which is for
                // saying so on the page and never for finding a row.
                table.column("author_name", .text).notNull()
                // The article's identity as the sender's device knows it, which
                // is what lets a recipient who follows the same source
                // recognize their own copy.
                table.column("guid", .text).notNull()
                table.column("title", .text).notNull()
                table.column("url", .text)
                table.column("excerpt", .text)
                table.column("author", .text)
                table.column("published_at", .datetime)
                table.column("image_url", .text)
                table.column("feed_url", .text)
                table.column("source_title", .text)
                table.column("received_at", .datetime).notNull()
            }

            // One person's list is written whole every time it changes, so what
            // this answers is : everything in this zone, and everything in it
            // from that person.
            try db.create(
                index: "shared_entry_on_zone_list",
                on: "shared_entry",
                columns: ["zone_name", "list_key"]
            )
            try db.create(
                index: "shared_entry_on_zone_guid",
                on: "shared_entry",
                columns: ["zone_name", "guid"],
                options: .unique
            )
        }

        // Where a source used to be served.
        //
        // **A column, because a move has to travel.** Every record about a
        // source is named after the address it is served at, so a source that
        // moves is a record under a new name and a deletion under the old one,
        // which on another device reads as one subscription removed and another
        // one added : the articles of the old row would go, and with them
        // everything the reader had ever said about the ones the new address no
        // longer serves. The record carries where the source came from instead,
        // so a device that receives it moves the row it already has and the
        // deletion that follows finds nothing left to take.
        //
        // It is never cleared. A device that has been switched off for a year
        // is exactly the one that needs it, and one that has already followed
        // the move finds nothing at the old address and does nothing.
        migrator.registerMigration("v29.aSourceThatMoved") { db in
            try db.alter(table: "feed") { table in
                table.add(column: "previous_url", .text)
            }
        }

        // A source the reader wants to be interrupted for.
        //
        // **On the feed and not in the preferences.** It is a decision about a
        // publisher, like the favourite beside it, and the record about that
        // source is where a decision about it belongs : a list of identifiers
        // in the key-value store would be a second place naming sources, going
        // stale the moment one is unsubscribed from and needing a rule of its
        // own for what happens when one moves.
        //
        // Off for every source there is, which is what a reader who has never
        // asked for a notification means.
        migrator.registerMigration("v30.aSourceWorthInterrupting") { db in
            try db.alter(table: "feed") { table in
                table.add(column: "notifies_new_articles", .boolean).notNull().defaults(to: false)
            }
            // Only the few sources that announce are ever asked for, on every
            // pass that brings articles, so the question is answered by an
            // index over almost nothing rather than by a scan of the sources.
            try db.create(
                index: "feed_announcing",
                on: "feed",
                columns: ["notifies_new_articles"],
                condition: Column("notifies_new_articles") == true
            )
        }

        // A writer the reader wants to be told about.
        //
        // **A table of its own, and not a column on the favourites.** The two
        // are different judgements, exactly as they are for a source : a
        // favourite writer is somebody the reader wants gathered on a page,
        // and this is somebody they want to be interrupted for. A flag on
        // `favourite_author` would have meant making somebody a favourite in
        // order to hear from them, and a row there whose flag said `no` to both
        // questions would be a favourite that is not one : the presence of that
        // row is the whole of what it says.
        //
        // Named after the writer like everything else about them. There is no
        // row per person and there could not be one : what a feed hands over is
        // a byline, so the name is the identity, matched exactly.
        migrator.registerMigration("v31.aWriterWorthInterrupting") { db in
            try db.create(table: "notified_author") { table in
                table.primaryKey("id", .blob)
                table.column("name", .text).notNull().unique()
                table.column("created_at", .datetime).notNull()
            }
        }

        // **Who an article is about, which no feed ever says.** A byline is a
        // field, and the people in the prose are not : they are read out of the
        // headline, the standfirst and the text, by `NLTagger` and by rules
        // that are mechanical the whole way down. `Newsmaker` is what reads
        // them and `docs/technical/newsmakers.md` is why it reads them that way.
        //
        // **The column is the resume point, and no rows is not the same
        // answer.** Reading a person out of an article costs a model pass over
        // the whole of its text, which is far too much to do inside the write
        // that stores the article : it is the resumable job of section 15
        // instead. `newsmakers_at` is what says an article has been read, since
        // an article that names nobody is a real answer and one told apart from
        // it only by having no rows would be read again at every pass, for ever.
        //
        // **Nothing is filled in here.** v26 could put the writers beside a
        // hundred thousand articles inside its own migration, because splitting
        // a byline is a handful of string operations over a few thousand
        // distinct spellings. This is a model over every article there is, and
        // a migration is the one place it may not run : it would hold the
        // launch. The job fills the corpus in afterwards, a batch at a time.
        migrator.registerMigration("v32.whoTheArticlesAreAbout") { db in
            try db.create(table: "entry_newsmaker") { table in
                table.column("entry_id", .blob).notNull().references("entry", onDelete: .cascade)
                table.column("name", .text).notNull().indexed()
                // How many times the article named them, which is what orders
                // the people of one piece : whoever it is about is named all
                // the way through it, and the expert quoted in the eleventh
                // paragraph is named once.
                table.column("mentions", .integer).notNull()
                table.primaryKey(["entry_id", "name"])
            }

            try db.alter(table: "entry") { table in
                table.add(column: "newsmakers_at", .datetime)
            }
            // What the job asks for on every batch, which is the articles that
            // have not been read yet.
            try db.create(index: "entry_on_newsmakers_at", on: "entry", columns: ["newsmakers_at"])

            // The two decisions, one table apiece and for the same reasons as
            // the writers' : a favourite gathers a page and an alert interrupts,
            // and the presence of the row is the whole of what it says.
            try db.create(table: "favourite_newsmaker") { table in
                table.primaryKey("id", .blob)
                table.column("name", .text).notNull().unique()
                table.column("created_at", .datetime).notNull()
            }
            try db.create(table: "notified_newsmaker") { table in
                table.primaryKey("id", .blob)
                table.column("name", .text).notNull().unique()
                table.column("created_at", .datetime).notNull()
            }
        }

        return migrator
    }

    /// Writes every stored byline the way ``Author/name(from:)`` spells it.
    ///
    /// A pass over the distinct spellings rather than over the articles : a
    /// corpus of a hundred thousand pieces carries a few thousand bylines, and
    /// the ones already clean are the great majority and are not written at all.
    private static func normalizeBylines(_ db: Database) throws {
        for spelling in try String.fetchAll(db, sql: "SELECT DISTINCT author FROM entry WHERE author IS NOT NULL") {
            let name = Author.name(from: spelling)
            guard name != spelling else { continue }
            try db.execute(sql: "UPDATE entry SET author = ? WHERE author = ?", arguments: [name, spelling])
        }
    }

    /// The same article, arriving twice.
    ///
    /// A paper that publishes a feed per desk puts the same piece in several
    /// of them, and a reader following two desks read it twice. The second
    /// copy keeps its row, because it belongs to a feed the reader follows and
    /// unsubscribing from that feed must take it away, but it points at the
    /// first and is shown nowhere.
    ///
    /// `ON DELETE SET NULL` : when the first copy is purged by age, the second
    /// stops being a duplicate of anything and becomes the article.
    private static func addDuplicates(_ db: Database) throws {
        try db.alter(table: "entry") { table in
            table.add(column: "canonical_key", .text)
            table.add(column: "duplicate_of", .blob).references("entry", onDelete: .setNull)
        }
        try db.create(index: "entry_on_canonical_key", on: "entry", columns: ["canonical_key"])
    }

    /// The subjects there are, as a vocabulary rather than a reading.
    ///
    /// The model used to name the subjects of the whole page on every
    /// rebuild, so they drifted : `Sécurité informatique` one run and
    /// `Cybersécurité` the next, and the preference the reader had attached to
    /// the first was left hanging off a name nothing used any more.
    ///
    /// A subject is a thing now. It is written once, it stays, and a story is
    /// sorted into it once and keeps it. The reader may add subjects of their
    /// own, which are theirs to delete ; the model may add one when nothing it
    /// is shown fits, and never renames what is already here.
    private static func createVocabulary(_ db: Database) throws {
        try db.create(table: "topic") { table in
            table.primaryKey("name", .text)
            table.column("is_own", .boolean).notNull().defaults(to: false)
            table.column("created_at", .datetime).notNull()
        }

        // Everything the model has already found becomes the first vocabulary,
        // so a reader upgrading keeps the subjects and the preferences on them.
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO topic (name, is_own, created_at)
                SELECT DISTINCT name, 0, CURRENT_TIMESTAMP FROM story_topic
                """
        )
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO topic (name, is_own, created_at)
                SELECT DISTINCT name, 0, CURRENT_TIMESTAMP FROM topic_preference
                """
        )
    }

    /// Keys the articles that were already here, and marks the copies.
    ///
    /// The column arrived empty and only new articles were keyed, so a reader
    /// who had been running Flong for a week kept every copy they already had
    /// : the fault they would report, and did.
    ///
    /// One pass over the stream. It costs a second on a large one, once, which
    /// is cheaper than the machinery of a resumable job for something that
    /// never runs again.
    static func keyExistingArticles(_ db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT e.id AS id, e.url AS url, e.title AS title, e.published_at AS published_at,
                       COALESCE(f.site_url, f.url) AS site_url
                FROM entry e JOIN feed f ON f.id = e.feed_id
                WHERE e.canonical_key IS NULL
                """
        )

        for row in rows {
            let key = ArticleKey.of(
                url: (row["url"] as String?).flatMap(URL.init(string:)),
                title: row["title"] as String? ?? "",
                publishedAt: row["published_at"] as Date?,
                room: FeedURL.room(of: (row["site_url"] as String?).flatMap(URL.init(string:)))
            )
            guard let key else { continue }
            try db.execute(
                sql: "UPDATE entry SET canonical_key = ? WHERE id = ?",
                arguments: [key, row["id"] as UUID]
            )
        }

        // The earliest copy of each key is the article ; the rest point at it.
        try db.execute(
            sql: """
                UPDATE entry AS e
                SET duplicate_of = (
                    SELECT o.id FROM entry o
                    WHERE o.canonical_key = e.canonical_key
                    ORDER BY o.received_at, o.id LIMIT 1
                )
                WHERE e.canonical_key IS NOT NULL
                  AND e.id <> (
                    SELECT o.id FROM entry o
                    WHERE o.canonical_key = e.canonical_key
                    ORDER BY o.received_at, o.id LIMIT 1
                  )
                """
        )
    }

    /// The subjects a story falls under, which are more than one.
    ///
    /// A column held exactly one, which is not how a page reads : a security
    /// advisory about a stolen database is under both computer security and
    /// cybercrime, and a reader who asked for more of either means this one.
    ///
    /// What the single column held is carried over rather than thrown away,
    /// so a page already sorted stays sorted until the next rebuild.
    private static func createStoryTopics(_ db: Database) throws {
        try db.create(table: "story_topic") { table in
            table.column("story_id", .blob).notNull().references("story", onDelete: .cascade)
            table.column("name", .text).notNull()
            table.primaryKey(["story_id", "name"])
        }
        try db.create(index: "story_topic_on_name", on: "story_topic", columns: ["name"])

        try db.execute(
            sql: """
                INSERT OR IGNORE INTO story_topic (story_id, name)
                SELECT id, topic FROM story WHERE topic IS NOT NULL
                """
        )
        // The index of the single column goes with the column it indexes, or
        // SQLite refuses the drop and leaves the schema half changed.
        try db.execute(sql: "DROP INDEX IF EXISTS story_on_topic")
        try db.alter(table: "story") { table in
            table.drop(column: "topic")
        }
    }

    /// What the reader wants more or less of.
    ///
    /// Keyed by the name of the subject, since a subject has nothing else to
    /// be known by : it is written afresh by the model on each rebuild, and
    /// the reader pressed on a word rather than on a row of a table.
    ///
    /// Nought is the absence of an opinion and is never stored, so the table
    /// holds one row per subject the reader has actually spoken about.
    private static func createTopicPreferences(_ db: Database) throws {
        try db.create(table: "topic_preference") { table in
            table.primaryKey("name", .text)
            table.column("score", .integer).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }

    /// Asks the model about every story once more.
    ///
    /// A build in between wrote briefs in the language of the articles and
    /// stamped them with the language of the reader, so they read as answered
    /// and nothing would ever have asked again : a page of English headlines
    /// for a French reader, permanently. Forgetting what was asked costs one
    /// question per story, once.
    private static func askAgain(_ db: Database) throws {
        try db.execute(sql: "UPDATE story SET brief_locale = NULL")
    }

    /// What the server last said about each record it holds.
    ///
    /// CloudKit refuses a record that carries no change tag when it already
    /// has one under that name : `record to insert already exists`. A record
    /// built from the store alone carries none, so every second save of
    /// anything was refused, for ever. The tag travels inside the system
    /// fields of the record the server hands back, which is what is kept here.
    ///
    /// It is a cache : losing it costs one refused save per record, after
    /// which the server hands the record back and the tag is learned again.
    private static func createRecordTags(_ db: Database) throws {
        try db.create(table: "sync_record") { table in
            table.primaryKey("record_name", .text)
            table.column("system_fields", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }

    /// The language a brief was written in.
    ///
    /// A brief is written in the reader's language, and a reader who changes it
    /// would otherwise keep yesterday's for ever : nothing else about the story
    /// has changed, so nothing else would ask for it to be written again.
    private static func addBriefLanguage(_ db: Database) throws {
        try db.alter(table: "story") { table in
            table.add(column: "brief_locale", .text)
        }
    }

    /// The subject a story falls under, when the model found one.
    ///
    /// A column on the story rather than a table of its own : a story is under
    /// exactly one subject, subjects are derived data that is never
    /// synchronized, and the whole set is rewritten every time the page is
    /// rebuilt. A table would be three joins to say what a string says.
    private static func addTopics(_ db: Database) throws {
        try db.alter(table: "story") { table in
            table.add(column: "topic", .text)
        }
        try db.create(index: "story_on_topic", on: "story", columns: ["topic"])
    }

    /// The picture that stands for an article.
    ///
    /// An address, never the file : the bytes belong to the publisher and are
    /// asked for only when a screen shows them. It travels to the library with
    /// the rest, so a kept article still has its illustration once the stream
    /// row it came from has been purged.
    private static func addCovers(_ db: Database) throws {
        try db.alter(table: "entry") { table in
            table.add(column: "image_url", .text)
        }
        try db.alter(table: "library_item") { table in
            table.add(column: "image_url", .text)
        }
    }

    /// The stories of the digest.
    ///
    /// A story is a group of articles about one event, and its signature is the
    /// vocabulary its articles share. Section 11 proposed vectorizing a recent
    /// window of the stream for this ; measurement said otherwise, and
    /// `TextSignature` says why.
    ///
    /// Stories are derived data. They are never synchronized, any more than the
    /// full-text index is : another device holds the same articles and works out
    /// the same stories, and sending them would cost records to say what the
    /// other end already knows.
    private static func createStories(_ db: Database) throws {
        try db.create(table: "story") { table in
            table.primaryKey("id", .blob)
            table.column("title", .text).notNull()
            table.column("summary", .text)
            // Section 14 : anything produced automatically says so, in the
            // interface and in exports.
            table.column("is_generated", .boolean).notNull().defaults(to: false)
            // Set when the reader has said they would rather have the article's
            // own headline, so the model does not write over their choice.
            table.column("brief_locked", .boolean).notNull().defaults(to: false)

            // The vocabulary the story's articles share, as terms and weights.
            table.column("signature", .jsonText)

            table.column("article_count", .integer).notNull().defaults(to: 0)
            table.column("feed_count", .integer).notNull().defaults(to: 0)
            table.column("first_at", .datetime).notNull()
            table.column("last_at", .datetime).notNull()
            table.column("updated_at", .datetime).notNull()
        }

        try db.create(index: "story_on_last_at", on: "story", columns: ["last_at"])

        try db.create(table: "story_member") { table in
            table.column("story_id", .blob).notNull().references("story", onDelete: .cascade)
            table.column("entry_id", .blob).notNull().references("entry", onDelete: .cascade)
            table.column("similarity", .double).notNull()
            table.primaryKey(["story_id", "entry_id"])
        }

        // An article belongs to one story at most : two would mean showing the
        // same article twice in a digest that exists to show less.
        try db.create(index: "story_member_on_entry", on: "story_member", columns: ["entry_id"], options: .unique)
    }

    /// The read states, as one row per period rather than one per article.
    ///
    /// `read_state` of v1 was written for one row per feed and per month, and
    /// was never used. One row per month, over every feed, is what actually
    /// meets the record budget of section 7 : three years of reading is a few
    /// dozen records instead of several thousand. It is replaced rather than
    /// altered, nothing having ever been stored in it.
    private static func createReadStateBlocks(_ db: Database) throws {
        try db.create(table: "read_state_block") { table in
            // The month the articles were published in, which every device
            // works out alike, or `undated`.
            table.column("period", .text).notNull()
            table.column("kind", .text).notNull()
            // The compressed set of fingerprints.
            table.column("fingerprints", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
            table.primaryKey(["period", "kind"])
        }

        try db.drop(table: "read_state")
    }

    /// The full-text index of the stream, and the triggers that keep it in step.
    ///
    /// The table is **contentless** rather than external content : it holds an
    /// index and not a second copy of the articles, which is what section 11 of
    /// the specification is after, and `contentless_delete` lets a row go on its
    /// identifier alone. External content would demand the exact original text
    /// back on every delete, and a cascade that has already removed the body has
    /// nothing to give back. That is how a full-text index quietly corrupts
    /// itself.
    ///
    /// `porter` wraps `unicode61`, so `reforme` finds `réforme` and `calendrier`
    /// finds `calendriers`. The stemmer is English, the only one SQLite ships :
    /// close enough on French suffixes to be worth having, and a per-language
    /// index is what doing better would take.
    private static func createSearchIndex(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE VIRTUAL TABLE entry_fts USING fts5(
                    title, excerpt, body, author,
                    content='', contentless_delete=1,
                    tokenize='porter unicode61 remove_diacritics 2',
                    prefix='2 3'
                )
                """
        )

        // What is already in the store, indexed once.
        try db.execute(sql: "\(indexInsert) \(indexSelect) WHERE 1")

        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_insert AFTER INSERT ON entry BEGIN
                    \(indexInsert) \(indexSelect) WHERE e.id = new.id;
                END
                """
        )
        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_update AFTER UPDATE OF title, excerpt, author ON entry BEGIN
                    DELETE FROM entry_fts WHERE rowid = old.rowid;
                    \(indexInsert) \(indexSelect) WHERE e.id = new.id;
                END
                """
        )
        try db.execute(
            sql: """
                CREATE TRIGGER entry_fts_after_delete AFTER DELETE ON entry BEGIN
                    DELETE FROM entry_fts WHERE rowid = old.rowid;
                END
                """
        )

        // The body arrives after its article and changes on its own, so it
        // reindexes the whole row rather than one column of it.
        for (name, event, row) in [
            ("entry_body_fts_after_insert", "AFTER INSERT ON entry_body", "new"),
            ("entry_body_fts_after_update", "AFTER UPDATE OF plain_text ON entry_body", "new"),
            ("entry_body_fts_after_delete", "AFTER DELETE ON entry_body", "old"),
        ] {
            try db.execute(
                sql: """
                    CREATE TRIGGER \(name) \(event) BEGIN
                        DELETE FROM entry_fts WHERE rowid = (SELECT rowid FROM entry WHERE id = \(row).entry_id);
                        \(indexInsert) \(indexSelect) WHERE e.id = \(row).entry_id;
                    END
                    """
            )
        }
    }

    /// The one shape every write to the index takes.
    ///
    /// Trigger and rebuild share it, so the index can never end up holding
    /// different columns depending on which of them wrote the row.
    static let indexInsert = "INSERT INTO entry_fts(rowid, title, excerpt, body, author)"
    static let indexSelect = """
        SELECT e.rowid, e.title, e.excerpt, b.plain_text, e.author
        FROM entry e LEFT JOIN entry_body b ON b.entry_id = e.id
        """

    /// The stream : feeds and their articles, a cache bounded in age and volume.
    private static func createStream(_ db: Database) throws {
        try db.create(table: "feed") { table in
            table.primaryKey("id", .blob)
            table.column("url", .text).notNull().unique()
            table.column("site_url", .text)
            table.column("icon_url", .text)
            table.column("title", .text).notNull()
            table.column("folder", .text)
            table.column("language", .text)

            // HTTP conditionality, sent back on the next request.
            table.column("etag", .text)
            table.column("last_modified", .text)

            // Health, as surfaced in the feed settings. The 304 rate is
            // `not_modified_count` over `fetch_count`.
            table.column("fetch_count", .integer).notNull().defaults(to: 0)
            table.column("not_modified_count", .integer).notNull().defaults(to: 0)
            table.column("failure_count", .integer).notNull().defaults(to: 0)
            table.column("last_failure_reason", .text)
            table.column("last_fetch_at", .datetime)
            table.column("last_success_at", .datetime)
            table.column("quarantined_at", .datetime)

            // Scheduling : the observed median publication gap, and the manual
            // override that wins over it. Both in seconds.
            table.column("observed_interval", .double)
            table.column("refresh_interval", .double)

            // Local settings, never synchronized.
            table.column("reader_mode_enabled", .boolean).notNull().defaults(to: false)
            table.column("loads_images", .boolean).notNull().defaults(to: true)

            table.column("created_at", .datetime).notNull()
        }

        try db.create(table: "entry") { table in
            table.primaryKey("id", .blob)
            table.column("feed_id", .blob).notNull().indexed().references("feed", onDelete: .cascade)

            // The stable identity of the article : its GUID, or the link and the
            // publication date when the feed serves none.
            table.column("guid", .text).notNull()

            table.column("url", .text)
            table.column("title", .text).notNull()
            table.column("excerpt", .text)
            table.column("author", .text)
            table.column("language", .text)
            table.column("published_at", .datetime)
            table.column("updated_at", .datetime)
            table.column("received_at", .datetime).notNull()

            table.column("is_read", .boolean).notNull().defaults(to: false)
            table.column("read_at", .datetime)
            table.column("is_starred", .boolean).notNull().defaults(to: false)
            table.column("is_hidden", .boolean).notNull().defaults(to: false)

            // Enclosures travel with their article and are only ever read whole,
            // so they stay a JSON array rather than a table of their own.
            table.column("enclosures", .jsonText)
            table.column("has_media", .boolean).notNull().defaults(to: false)
        }

        try db.create(index: "entry_on_feed_guid", on: "entry", columns: ["feed_id", "guid"], options: .unique)
        try db.create(index: "entry_on_published_at", on: "entry", columns: ["published_at"])
        try db.create(
            index: "entry_unread",
            on: "entry",
            columns: ["received_at"],
            condition: Column("is_read") == false
        )
        try db.create(
            index: "entry_starred",
            on: "entry",
            columns: ["received_at"],
            condition: Column("is_starred") == true
        )

        try db.create(table: "entry_body") { table in
            table.primaryKey("entry_id", .blob).references("entry", onDelete: .cascade)
            table.column("sanitized_html", .text)
            table.column("extracted_html", .text)
            table.column("plain_text", .text)
        }
    }

    /// The library : what the user chose to keep, frozen at the moment of promotion.
    ///
    /// A library item repeats the title, the author and the feed of its article
    /// on purpose. The stream row it came from is purged by age, and the source
    /// itself may disappear ; neither may take the kept copy with it.
    private static func createLibrary(_ db: Database) throws {
        try db.create(table: "library_item") { table in
            table.primaryKey("id", .blob)
            table.column("entry_id", .blob).references("entry", onDelete: .setNull)

            table.column("feed_url", .text)
            table.column("feed_title", .text)
            table.column("guid", .text).notNull().indexed()
            table.column("url", .text)
            table.column("title", .text).notNull()
            table.column("author", .text)
            table.column("language", .text)
            table.column("published_at", .datetime)
            table.column("promoted_at", .datetime).notNull()

            table.column("content_html", .text)
            table.column("plain_text", .text)
            table.column("annotation", .text)

            // A vector only compares to vectors of the same model and revision,
            // so both travel with it and a mismatch means recomputing locally.
            table.column("vector", .blob)
            table.column("vector_model", .text)
            table.column("vector_revision", .text)
        }
    }

    /// Tags, rules and saved queries.
    private static func createOrganization(_ db: Database) throws {
        try db.create(table: "tag") { table in
            table.primaryKey("id", .blob)
            table.column("path", .text).notNull().unique()
            table.column("created_at", .datetime).notNull()
        }

        // A tag applies to an article, a feed or a library item, so the binding
        // carries the kind of what it points at rather than three foreign keys.
        try db.create(table: "tag_binding") { table in
            table.column("tag_id", .blob).notNull().references("tag", onDelete: .cascade)
            table.column("target_kind", .text).notNull()
            table.column("target_id", .blob).notNull()
            table.column("created_at", .datetime).notNull()
            table.primaryKey(["tag_id", "target_kind", "target_id"])
        }

        try db.create(index: "tag_binding_on_target", on: "tag_binding", columns: ["target_kind", "target_id"])

        try db.create(table: "rule") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull()
            table.column("query", .text).notNull()
            table.column("actions", .jsonText).notNull()
            table.column("position", .integer).notNull()
            table.column("is_enabled", .boolean).notNull().defaults(to: true)
            table.column("created_at", .datetime).notNull()
            table.column("last_run_at", .datetime)
        }

        try db.create(table: "saved_query") { table in
            table.primaryKey("id", .blob)
            table.column("name", .text).notNull().unique()
            table.column("query", .text).notNull()
            table.column("position", .integer).notNull()
            table.column("created_at", .datetime).notNull()
        }
    }

    /// Read states and the synchronization tokens.
    ///
    /// Read states are compacted into one row per feed, per month and per kind.
    /// That is what keeps the CloudKit record count in the three thousand range
    /// instead of one record per article, and merging two of these rows is a
    /// union, so it needs no conflict resolution.
    private static func createSyncState(_ db: Database) throws {
        try db.create(table: "read_state") { table in
            table.primaryKey("id", .blob)
            table.column("feed_id", .blob).notNull().references("feed", onDelete: .cascade)
            table.column("period", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("fingerprints", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }

        try db.create(
            index: "read_state_on_feed_period_kind",
            on: "read_state",
            columns: ["feed_id", "period", "kind"],
            options: .unique
        )

        try db.create(table: "sync_state") { table in
            table.primaryKey("key", .text)
            table.column("value", .blob).notNull()
            table.column("updated_at", .datetime).notNull()
        }
    }
}
