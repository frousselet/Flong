# FreshRSS API

Flong is not a FreshRSS client. It has no backend, and it keeps no permanent link with any service. This page documents the API used for the one-shot import of an existing account, described in section 19 of the specification and scheduled for M7.

That surface is the Google Reader compatible API, not the native FreshRSS API and not the Fever one. It is also served by Miniflux, Inoreader, The Old Reader and BazQux, so one import implementation covers several services.

There is no specification to work from. Google never published or documented this API, and Google Reader shut down in July 2013. FreshRSS's own developer page is deliberately short and points at archived third-party write-ups. **The authority for everything below is the FreshRSS implementation itself**, read at version 1.29.1 :

- `p/api/greader.php` : routing, parameters, and the JSON of `tagList`, `subscriptionList`, `unreadCount` and `streamContents`.
- `app/Models/Entry.php` : `FreshRSS_Entry::toGReader`, which produces every article object.
- `app/Models/EntryDAO.php` : `markReadEntries`, which defines what `mark-all-as-read` actually compares.

Where the implementation contradicts its own comments, the implementation wins. One such case is called out below.

## Enabling the API

1. **Settings, Authentication** : tick *Allow API access for external clients*.
2. **Profile** : set an *API password*, which is distinct from the web password.

## Base URL and authentication

Everything hangs off `{instance}/api/greader.php`.

### Opening a session

```
POST {instance}/api/greader.php/accounts/ClientLogin
Content-Type: application/x-www-form-urlencoded

Email=<username>&Passwd=<api password>
```

The reply is `text/plain`, three lines :

```
SID=alice/8e6845e089457af25303abc6f53356eb60bdb5f8
LSID=null
Auth=alice/8e6845e089457af25303abc6f53356eb60bdb5f8
```

Only `Auth` matters. The token is `<username>/<sha1>` and does not expire on its own. A wrong password answers **401**, an unknown username answers **400**, so a client should treat both as rejected credentials. `GET` is accepted but deprecated : the server logs a warning because the password would appear in access logs.

### Authenticating requests

```
Authorization: GoogleLogin auth=<token>
```

A 401 or 403 on any other endpoint means the session is gone : sign in again and replay once.

### Modification token

Write endpoints require a second token, fetched from `GET reader/api/0/token` and sent as the `T` form field. The reply is a 57 character string **followed by a newline**, which must be trimmed before use. FreshRSS derives it from the account salt and never expires it, but its source carries a note about implementing expiry, so a client should refresh it rather than cache it forever.

## Identifiers

| Object | Form | Note |
| ------ | ---- | ---- |
| Feed | `feed/<numeric id>` | **Not** `feed/<url>`. The feed URL travels separately in the `url` field. |
| Folder | `user/-/label/<name>` | |
| Article label | `user/-/label/<name>` | Same prefix as a folder : only `tag/list` can tell them apart. |
| Article | `tag:google.com,2005:reader/item/<16 hex digits>` | Zero padded, lowercase, two's complement over 64 bits for negative values. |

Built-in streams : `user/-/state/com.google/reading-list`, `.../starred`, `.../read`. FreshRSS also serves `user/-/state/org.freshrss/main` and `.../important`.

### The two article identifier forms

`stream/contents` returns the long form above, while `stream/items/ids` returns the plain decimal identifier. A client mixing the two endpoints has to convert : the long form is `str_pad(dechex($id), 16, '0', STR_PAD_LEFT)`.

`edit-tag` accepts either. It treats a value as decimal when it is all digits and does not start with `0`, and otherwise strips the prefix and reads it as hexadecimal. Round-tripping the long form untouched is therefore always safe, and is what an importer should do.

## Endpoints

`output=json` is **mandatory** on `subscription/list`, `tag/list` and `unread-count` : without it the server answers 501.

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET | `reader/api/0/user-info` | Account information |
| GET | `reader/api/0/subscription/list` | Feeds, with their folder, URLs and icon |
| GET | `reader/api/0/tag/list` | Built-in states, folders and article labels |
| GET | `reader/api/0/unread-count` | Unread counts per feed, per folder, per label, plus a total |
| GET | `reader/api/0/stream/contents/<stream>` | Articles with their content |
| GET | `reader/api/0/stream/items/ids` | Identifiers only, for cheap state reconciliation |
| POST | `reader/api/0/edit-tag` | Add or remove a state on articles |
| POST | `reader/api/0/mark-all-as-read` | Mark a stream as read |
| POST | `reader/api/0/subscription/edit` | Subscribe, unsubscribe, rename, move |
| POST | `reader/api/0/subscription/quickadd` | Subscribe from a URL |
| POST | `reader/api/0/rename-tag` | Rename a folder or label |
| POST | `reader/api/0/disable-tag` | Delete a folder or label |

### Reading a stream

The stream identifier goes **into the path with its separators intact**. FreshRSS explodes the path on `/` and matches segment by segment, so percent-encoding the identifier as a single component makes the route fail. Only the trailing name is escaped :

```
GET reader/api/0/stream/contents/user/-/state/com.google/reading-list
GET reader/api/0/stream/contents/user/-/label/Tech%20news
GET reader/api/0/stream/contents/feed/42
```

A `?s=<stream id>` query parameter is accepted instead, for BazQux compatibility, but the server splits that value on `/` too, so it is unreliable for a feed whose identifier contains slashes.

| Parameter | Meaning |
| --------- | ------- |
| `n` | Number of items. **Defaults to 20** when absent. The server sets no maximum of its own. |
| `c` | Continuation token from the previous page. Must be all digits : anything else is silently reset, restarting the stream. |
| `xt` | Exclude a state, typically `user/-/state/com.google/read` for unread only |
| `it` | Include only a state |
| `ot` | Only items newer than this Unix timestamp |
| `nt` | Only items older than this Unix timestamp |
| `r` | `d` or `n` for newest first, `o` for oldest first |

`continuation` is present **only when the page was filled**, and holds the last article's decimal identifier. Its absence is the end of the stream.

### Article objects

FreshRSS serializes in compatibility mode, which has two consequences a client must handle :

- the body lands in `summary.content`, and **`content` is absent**. Servers that do not use compatibility mode put the full body in `content` instead, so read `content` first and fall back to `summary`.
- the body is capped at 500 000 bytes, which is a safety limit rather than a practical truncation.

`updated` is commented out in the implementation and never sent. Useful fields :

| Field | Type | Note |
| ----- | ---- | ---- |
| `id` | string | Long form |
| `title` | string | |
| `author` | string | Absent when the article has none |
| `published` | number | Seconds since the epoch |
| `crawlTimeMsec` | string | Insertion date in milliseconds |
| `timestampUsec` | string | Insertion date in microseconds, and the article's decimal identifier |
| `summary.content` | string | HTML body |
| `canonical[].href`, `alternate[].href` | string | Article link |
| `origin.streamId` | string | `feed/<numeric id>`, matching `subscription/list` |
| `origin.title`, `origin.htmlUrl` | string | |
| `categories[]` | array of strings | States and labels, see below |
| `enclosure[]` | array | Media attachments, with `href`, `type` and optional `length` |

`categories` always opens with `user/-/state/com.google/reading-list` and then carries the feed's folder, the FreshRSS priority states, `user/-/state/com.google/read` when read, `user/-/state/com.google/starred` when starred, and any article label. Read and starred state is derived from this array, nowhere else.

### tag/list

Three kinds of entry share one array :

| Kind | Shape |
| ---- | ----- |
| Built-in states | `{"id": "user/-/state/com.google/starred"}`, with **no** `type` |
| Folder | `{"id": "user/-/label/News", "type": "folder"}` |
| Article label | `{"id": "user/-/label/To read", "type": "tag", "unread_count": 3}` |

Folders and labels share the `user/-/label/` prefix, so `type` is the only thing separating them. Keeping the entries typed `folder` is the correct rule, and treating untyped entries as folders would wrongly pick up the built-in states.

### subscription/list

`{"subscriptions": [{id, title, categories: [{id, label}], url, htmlUrl, iconUrl, "frss:priority"}]}`

`url` is the feed document, `htmlUrl` the site. A feed belongs to exactly one category in FreshRSS, so `categories` holds zero or one entry. Hidden feeds are omitted.

### unread-count

`{"max": <total>, "unreadcounts": [{id, count, newestItemTimestampUsec}]}`

One entry per feed, one per folder, one per label, and one for `user/-/state/com.google/reading-list` carrying the total. `count` is a number, `newestItemTimestampUsec` a string.

### Changing article state

```
POST reader/api/0/edit-tag
Content-Type: application/x-www-form-urlencoded

i=<article id>&i=<article id>&a=user/-/state/com.google/read&T=<token>
```

`i` repeats once per article, `a` adds a state, `r` removes one. Marking unread is removing the read state. A state that is neither read nor starred and starts with `user/-/label/` creates an article label, creating the label itself when needed.

FreshRSS sets no explicit ceiling on the number of `i` fields, but PHP silently drops input fields past `max_input_vars`, which defaults to 1000. Batching well below that keeps a large selection from being partially applied without any error.

### Marking a stream as read

```
POST reader/api/0/mark-all-as-read
Content-Type: application/x-www-form-urlencoded

s=<stream id>&ts=<microseconds since epoch>&T=<token>
```

**`ts` is in microseconds.** The dispatcher comments it as nanoseconds, but the value is passed straight through as an article identifier and compared with `WHERE id <= ?` in `EntryDAO::markReadEntries`, and a FreshRSS article identifier is its insertion date in microseconds. Sending nanoseconds would put the bound a thousandfold in the future and mark the entire account as read.

A feed stream must use the **numeric** form here : `markAllAsRead` rejects `feed/<url>` with a 400. Folders, labels, `reading-list` and `starred` are all accepted.
