# FreshRSS API

Flong talks to FreshRSS through the Google Reader compatible API, not through the native FreshRSS API and not through the Fever API. That choice is deliberate : the same surface is served by Miniflux, Inoreader, The Old Reader and others, so a single client implementation covers every future backend.

## Enabling the API

Two settings on the instance :

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

The response is plain text, not JSON :

```
SID=...
LSID=...
Auth=<token>
```

Only the `Auth` line matters. A failed login answers `401` and a body containing `Error=BadAuthentication`.

### Authenticating requests

Every subsequent call carries :

```
Authorization: GoogleLogin auth=<token>
```

A `401` or `403` on a request means the token is no longer valid : sign in again and replay the request once.

### Write token

Write endpoints also require a short-lived CSRF token, fetched from `GET reader/api/0/token` (plain text response) and sent as a `T` field in the form body. It expires, so it must be refreshed rather than cached for the life of the session.

## Stream identifiers

A stream is addressed by an identifier, which must be percent-encoded when it appears in a URL path (`/` and `:` included) :

| Stream | Identifier |
| ------ | ---------- |
| Every article | `user/-/state/com.google/reading-list` |
| Starred | `user/-/state/com.google/starred` |
| Read state | `user/-/state/com.google/read` |
| A folder | `user/-/label/<folder name>` |
| A feed | `feed/<feed url>` |

FreshRSS marks folders with `"type": "folder"` in `tag/list`, while article labels come back without a type. Other servers are not guaranteed to set the field, so a client should fall back to treating every `user/-/label/` entry as a folder when no entry carries a type.

## Endpoints

All read endpoints take `output=json`.

| Method | Path | Purpose |
| ------ | ---- | ------- |
| GET | `reader/api/0/user-info` | Account information |
| GET | `reader/api/0/subscription/list` | Feeds, with their folders, site URL and icon |
| GET | `reader/api/0/tag/list` | Folders and labels |
| GET | `reader/api/0/unread-count` | Unread counts per feed and per folder |
| GET | `reader/api/0/stream/contents/{stream}` | Articles of a stream, with their content |
| GET | `reader/api/0/stream/items/ids` | Article identifiers only, for cheap state reconciliation |
| POST | `reader/api/0/edit-tag` | Add or remove a state on articles |
| POST | `reader/api/0/mark-all-as-read` | Mark a whole stream as read |
| POST | `reader/api/0/subscription/edit` | Rename a feed, move it between folders, unsubscribe |
| POST | `reader/api/0/subscription/quickadd` | Subscribe to a feed URL |

### Reading a stream

`GET reader/api/0/stream/contents/{stream}` accepts :

| Parameter | Meaning |
| --------- | ------- |
| `n` | Number of items, capped by the server (1000 in practice) |
| `c` | Continuation token from the previous page |
| `xt` | Exclude a state, typically `user/-/state/com.google/read` to fetch unread only |
| `it` | Include only a state |
| `ot` | Only items newer than this Unix timestamp |
| `r` | Sort order, `o` for oldest first |

The response carries `items` and, when more pages exist, a `continuation` token to pass back as `c`.

Each item exposes its identifier, `title`, `author`, `published`, `crawlTimeMsec`, `timestampUsec`, the body under `summary.content` or `content.content`, the link under `canonical` or `alternate`, the source feed under `origin.streamId`, and its states under `categories`. Read and starred are read off that `categories` array.

Integer fields are not consistently typed across servers : some send them as JSON numbers, others as strings. Decode both.

### Changing article state

```
POST reader/api/0/edit-tag
Content-Type: application/x-www-form-urlencoded

i=<article id>&i=<article id>&a=user/-/state/com.google/read&T=<write token>
```

`i` repeats once per article, `a` adds a state and `r` removes one. Marking as unread is removing the read state, starring is adding the starred state. Servers limit how many identifiers a single call accepts, so batch them.

### Marking a stream as read

```
POST reader/api/0/mark-all-as-read
Content-Type: application/x-www-form-urlencoded

s=<stream id>&ts=<microseconds since epoch>&T=<write token>
```

`ts` bounds the operation to articles published before that instant, which avoids marking articles the server received while the request was in flight.

## To verify against a live instance

These points come from the API surface rather than from a run against a real FreshRSS instance, and should be confirmed before being relied on :

- the exact ceiling FreshRSS applies to `n` and to the number of `i` fields per `edit-tag` call,
- whether `mark-all-as-read` accepts a feed stream as well as a folder,
- the lifetime of the `T` write token,
- the shape of `iconUrl` in `subscription/list`, which is instance-relative on some deployments.
