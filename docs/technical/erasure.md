# Deleting everything

The one command in Flong that takes something away for good : what it reaches, in which order, and what it cannot promise.

## Why it exists

There is no account, so there is no account to close. A reader who wants out of a service closes it and the service forgets them ; a reader who wants out of Flong has nobody to ask, and the data is theirs, on their own devices and in their own iCloud. This is that command, and it is the only place in the application where something the reader kept is deleted rather than tidied.

It is not the purge. The purge frees space the stream is holding and spares everything marked, and is asked for from the sources panel where a reader thinking about disk is already standing. This deletes what the purge exists to protect.

## Where it lives

At the foot of the reader's panel, in a card of its own : red glass carrying the heading `Zone de danger` under a warning mark, the sentence that says what will go, and one prominent red button. Everything above it in that panel is what the reader chose about themselves ; this is them taking all of it back, which is the same conversation and belongs in the same place.

**It leaves the grouped form the settings sit in**, which is the point of the card. A setting is a thing a reader changes their mind about freely, and a row that looks like its neighbours is a row that is pressed like its neighbours. It is also the one place in the application where Liquid Glass is used to say danger rather than to float over a page, tinted at a third of the colour so the material still reads as glass and the button it holds stays the strongest red on screen. `docs/technical/interface.md` records why the exception is admitted here and nowhere else.

It asks before it acts, and the sentence it asks with names what goes rather than warning in the abstract : the subscriptions, the articles, what was kept, the sites signed in to, here and in iCloud. The confirmation is destructive and the panel closes when the work is done, so the reader lands on an application that looks like a first launch rather than on a settings page reporting a success.

## Six places hold something

Deleting fewer than all six is not a reset but a pause, since three of them would fill the other three back up at the next exchange.

| Where | What goes |
| ----- | --------- |
| The database | Every table, dropped and built again from the migrations : the feeds, the articles, the bodies, the stories, the subjects, the collections, the read states, and the tokens and record tags that told this device what iCloud already knew |
| The keychain | Every feed credential and every site session, deleted by service rather than one by one, so a secret whose subscription is already gone goes with the rest |
| The key-value store | Every preference, local and in iCloud : the name, the picture, which body an article opens on, the notices, and the identifier this device writes its archive under |
| Spotlight | The index of marked articles, emptied by the ordinary rebuild, which now writes nothing because there is nothing to write |
| The record zone | Deleted from the reader's private CloudKit database, through the engine's own pending database changes |
| iCloud Drive | The whole `Stream` folder, every device's days and not only this one's |

Two more are emptied because they hold the publishers' bytes rather than the reader's : the picture cache, memory and disk, and any notice still standing in the notification centre, which after a reset would be a headline that opens nothing.

## The order is the design

1. **Stop everything that writes.** The enrichment is cancelled and waited for, and the window stops following the store. Dropping tables under a `DatabaseRegionObservation` is how a window goes deaf for the rest of the process.
2. **Tell iCloud first**, while the change tokens that address the zone are still in the database that is about to be erased.
3. **Then this device** : the tables, the keychain, Spotlight, the notices, the pictures.
4. **The reader's own choices last**, since the window reads its name and its face back from them. Each is emptied through the window, which writes the empty value to the store, before the keys themselves are removed.
5. **Then back to work.** The page is read back from the empty store, the watcher and the clock start again, and the sync engine is started from nothing, which recreates an empty zone. An application that had to be relaunched after a reset would be saying the reset broke it.

The database file is emptied rather than deleted. Every store, every job and the observation hold one writer, and a new file would be a writer none of them has ; `erase()` and the migrations leave all of them pointing at a database that is simply empty.

## What it cannot promise

**Another device that still holds the subscriptions will put its copy back.** It finds the zone gone, reads that as `zoneNotFound`, recreates it and sends everything it has, which is the existing repair path and is correct : it is how a device recovers from a zone lost for any other reason, and there is no server to tell it that this one was deliberate.

The same is true of the archive : a device that still has the stream writes its own days out again the next time it exchanges.

This is a consequence of a design with no server in it, and the alert says so in a sentence before the reader confirms rather than promising a reach Flong does not have. A reader who wants everything gone everywhere runs the command on each of their devices, and the order does not matter.

## What is not touched

- **The system's answer about notifications.** Whether Flong may interrupt this reader is the system's to hold, in the system's own settings, and an application does not reach in there.
- **iCloud Keychain on other devices**, beyond the deletion this device propagates like any other keychain change.
- **Anything else in the key-value store.** The store belongs to the whole system and a reset of Flong is not a reason to touch what another application put in it.

## What is tested

The store comes back empty with its schema and its migrations, and takes writes again. Every preference is forgotten and the device identifier with it. The keychain keeps nothing back. And the window, after a reset, holds no feeds, no articles, no collections, no sessions, no name and no face, sits where a first launch puts it, and takes a new subscription exactly as it did before, which is the half that a reset merely emptying tables would get wrong.

The zone deletion and the archive deletion are the two that cannot be tested from the outside : both need an account, a container and a network, which is true of everything in `CloudSync` and is recorded in `docs/technical/sync.md`.
