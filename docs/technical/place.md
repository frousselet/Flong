# Where the reader is

A town and a country, under the reader's own face, beside their name. It is optional, it is empty until they answer, and nothing in the application asks for it yet : it is kept because the region somebody reads from is a fact about them, and the features that will want it want a region rather than a position.

## What is kept, and what is not

Three strings and nothing else : a town, a country, and the ISO 3166-1 code of that country.

**The name and the code answer different questions.** The name is what the reader is shown, and it arrives in whatever language their device is set to : MapKit says `Allemagne` to a French device and `Germany` to an English one. The code is what a rule, a query or a later feature would match on, and `DE` is `DE` on both. Keeping only the name would mean matching on a translated string, which is how a preference set on one device quietly stops working on the next. The code is dropped rather than guessed when MapKit does not give one, and anything that is not two ASCII letters is not kept as a third spelling of the country.

**One of the two names may be missing, and never both.** A fix in the middle of the North Sea has a country and no town. A place with neither is not a place, which is what makes the initializer of `Place` failable rather than a struct anybody can build empty.

**No coordinate survives the call.** The fix taken from the device is turned into a town and dropped in the same breath. This is the decision the rest of the page follows from : a latitude to five decimal places is the reader's street, it would travel to their iCloud with the rest of their preferences, and nothing planned would ever read it. What is wanted is the region, and the region is a name.

**No map, no monitoring, no background.** Nothing here follows the reader. The device is asked once, when they press the button, and the stream is closed by the first update that carries a location.

## Two ways to answer, and the typed one is the road

**Searching for a town needs no permission**, works on a Mac with no receiver in it and on a phone in aeroplane mode, and is the right answer for a reader who is on holiday and does not want their holiday recorded as where they live. The device's own answer is the shortcut, not the road, and a refusal leaves the reader in front of the search rather than in front of nothing.

### The suggestions

`MKLocalSearchCompleter`, which is what Apple asks be used while somebody is typing : it is cheap, and running a full search on every letter would spend a rate limit on nine answers the reader never looked at.

**It offers places and only coarse ones.** The result type is an address rather than a point of interest, and the address filter allows a country, a region, a town and a district and nothing finer, so a reader typing `Bar` is offered Barcelona and never a bar around the corner. The question is which region they read from, and a street is not an answer to it and is not a thing to keep.

**Choosing is what resolves.** A completion is two lines of display text with no structure in it : `Paris` and `Île-de-France, France` are strings, and taking the second half of the second line for a country would be reading tea leaves. The one suggestion the reader chose is run through `MKLocalSearch`, and the town, the country and the code are read off `MKAddressRepresentations`, where they are fields. Nothing is deduced from a display string, and a suggestion MapKit will say nothing structured about is reported rather than papered over with what it displayed.

**An empty field asks for nothing rather than for everything.** The completer is stopped and the list emptied, so a reader who cleared the field is not left looking at the answers to a question they took back. The list is only told there is nothing once the completer has actually answered : said while it is still thinking, that message would appear on every letter typed.

### The device

`CLLocationUpdate.liveUpdates()`, ended by the first update carrying a location. An update with no location is not a failure by itself : it is what arrives while the prompt is standing open and while the receiver is still working. A refusal and a flat "there is no location here" end it early ; everything else waits for the clock, which is twenty seconds, long enough for a cold fix and short enough that a spinner is not a hang.

`MKReverseGeocodingRequest` turns the fix into a town. `CLGeocoder` is deprecated as of this year's systems, and the address representations are the right half of the new API anyway : a town and a country are fields there, where a formatted line would have to be taken apart to get them back.

**The permission is asked for at the moment the reader presses the button**, which is the rule the notices already follow : a prompt at first launch is a prompt about something nobody has seen yet, and that is how an application is refused for good. A refusal already given is thrown straight back rather than waited on, since asking again does not prompt. `CLLocationManager` is held for the life of the locator rather than made and dropped, because on iOS the prompt belongs to the manager that asked for it and a manager released a line later takes its own prompt down with it.

On macOS the same code needs `com.apple.security.personal-information.location` in the entitlements, the sandbox being what it is. Nothing else differs : no feature exists on one platform alone.

## What leaves the device

**The fragment being typed, and the coordinate, go to Apple.** They have to : a completer and a geocoder are services, and there is no offline gazetteer in the system to ask instead. That is the whole of it. What comes back is not sent anywhere, and the place the reader chooses goes to their own iCloud with their other preferences and to nobody else. Section 20 of the specification says no data leaves the device apart from the private CloudKit database and the requests to the feeds ; this is the third of those, it is named here, and it happens only while the reader is choosing.

## Where it is kept

The iCloud key-value store, beside the name and the face, as three keys. Not a CloudKit record : section 7 gives the private database a budget of around three thousand records and it is spent on subscriptions, articles and read states.

**Three keys rather than one encoded blob.** The store holds strings, and a JSON payload in a preference is a thing that has to be versioned the first time a field is added to it. They are written and removed together, so a half-written place is never read back, and a place chosen without a code clears the code the last one had : otherwise Lisbon ends up filed under France.

It travels between the reader's devices for the same reason their name does, it is in the list of keys `forgetEverything()` removes, and deleting everything takes it with the rest.

## What a refusal does, and what it does not

**It says so where the reader is standing.** The shell's alert is two sheets below by the time the picker is open, and an alert presented from under a sheet is one nobody sees. So `AppModel.locate()` hands back a `PlaceFailure` instead of posting to `AppFailure`, and the picker says it. There are three of them and not one, because there are three different things for the reader to do about it : go to the system settings, type the name of their town, or pick a different one. A single "it did not work" would leave them with none of those.

**It changes nothing else.** Whatever the reader had chosen by hand stays chosen : the system declining to answer is not the reader taking their own answer back.
