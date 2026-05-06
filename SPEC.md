# Implementation Spec

This document pins down the implementation details that **`docs/openapi.yaml`** (the API contract) and **`database/migrations/`** (the schema) don't cover. Together with those two, this document fully specifies the backend — an implementation that follows all three should be byte-for-byte compatible with the reference frontend.

> Audience: developer (or AI agent) implementing the backend from scratch. Read this **after** the OpenAPI and migrations.

## 1. Stack

- **Framework:** Laravel 11+ (PHP 8.4)
- **Auth:** Laravel Sanctum (personal access tokens)
- **DB:** MySQL 8+
- **Storage:** local `public` disk, exposed via `php artisan storage:link`
- **HTTP server:** FrankenPHP (see `Dockerfile-Exemplo` and `docker/Caddyfile`)

Bootstrap the Sanctum table by running `php artisan install:api` after `composer create-project laravel/laravel`. That generates the `personal_access_tokens` migration; combined with the 5 migrations shipped in this template, the schema is complete.

## 2. Authentication

### Token issuance

Every login/register/refresh response uses this exact shape (see OpenAPI `TokenResponse`):

```json
{
  "access_token": "{id}|{random}",
  "token_type": "Bearer",
  "expires_in": <int|null>,
  "user": { ...User }
}
```

- Token created with `$user->createToken('api')->plainTextToken`. Name **must** be `"api"`.
- `expires_in` is computed from `config('sanctum.expiration')`:
  - If null → `expires_in: null` (tokens don't expire).
  - Otherwise → `expires_in: ((int) $minutes) * 60` (seconds).
- The token format `{id}|{random}` is Sanctum's default; do not customize.

### Logout

Delete `Auth::user()->currentAccessToken()` (cast to `PersonalAccessToken` before calling `delete()` — `TransientToken` should be ignored).

### Refresh

Delete the current token, then issue a new one (same shape as login).

### Routes that don't need auth

Only `POST /auth/register` and `POST /auth/login`. Everything else (including `POST /auth/logout` and `POST /auth/refresh`) is behind `auth:sanctum`.

## 3. Validation (FormRequest rules)

Implement these as Laravel `FormRequest` classes. The exact rule strings matter — Laravel's validation messages and `unique:` semantics depend on them.

### `Auth\RegisterRequest`

```php
'name'     => ['required', 'string', 'max:255'],
'username' => ['required', 'string', 'min:3', 'max:30', 'regex:/^[a-zA-Z0-9_.]+$/', 'unique:users,username'],
'email'    => ['required', 'string', 'email', 'max:255', 'unique:users,email'],
'password' => ['required', 'confirmed', Password::min(8)],
```

Custom message: `'username.regex' => 'The username may only contain letters, numbers, underscores and dots.'`

The `confirmed` rule requires the client to send `password_confirmation` (already documented in OpenAPI's `RegisterRequest`).

### `Auth\LoginRequest`

```php
'email'    => ['required', 'string', 'email'],
'password' => ['required', 'string'],
```

### `User\UpdateProfileRequest`

```php
$userId = $this->user()->getKey();

'name'     => ['sometimes', 'required', 'string', 'max:255'],
'username' => ['sometimes', 'required', 'string', 'min:3', 'max:30', 'regex:/^[a-zA-Z0-9_.]+$/', Rule::unique('users', 'username')->ignore($userId)],
'bio'      => ['sometimes', 'nullable', 'string', 'max:500'],
```

Same custom message as register for `username.regex`.

### `User\UploadAvatarRequest`

```php
'avatar' => ['required', 'image', 'mimes:jpeg,jpg,png,webp', 'max:2048'],
```

`max:2048` is **kilobytes** → 2 MB.

### `User\SearchUsersRequest`

```php
'q'        => ['required', 'string', 'min:2', 'max:50'],
'per_page' => ['sometimes', 'integer', 'min:1', 'max:50'],
```

### `Post\CreatePostRequest`

```php
'image'   => ['required', 'image', 'mimes:jpeg,jpg,png,webp', 'max:5120'],
'caption' => ['nullable', 'string', 'max:2200'],
```

`max:5120` → 5 MB.

### `Post\UpdatePostRequest`

```php
'caption' => ['sometimes', 'nullable', 'string', 'max:2200'],
```

### `Comment\CreateCommentRequest` and `Comment\UpdateCommentRequest`

Both extend an abstract `Comment\CommentBodyRequest` with:

```php
'body' => ['required', 'string', 'min:1', 'max:2200'],
```

## 4. Authorization (Policies)

Two policies, both pure ownership checks:

```php
// PostPolicy
public function update(User $user, Post $post): bool   { return $user->getKey() === $post->user_id; }
public function delete(User $user, Post $post): bool   { return $user->getKey() === $post->user_id; }

// CommentPolicy
public function update(User $user, Comment $comment): bool { return $user->getKey() === $comment->user_id; }
public function delete(User $user, Comment $comment): bool { return $user->getKey() === $comment->user_id; }
```

Wire via `$this->authorize('update', $post)` (or `$comment`) in the controller. A failed check produces Laravel's default 403 (`"This action is unauthorized."`).

## 5. Custom Exceptions (and their HTTP semantics)

Both extend `Symfony\Component\HttpKernel\Exception\HttpException` so Laravel renders the right status automatically.

```php
// App\Exceptions\InvalidCredentialsException — 401 "Invalid credentials."
class InvalidCredentialsException extends HttpException {
    public function __construct(string $message = 'Invalid credentials.') {
        parent::__construct(401, $message);
    }
}

// App\Exceptions\SelfFollowException — 403 "You cannot follow yourself."
class SelfFollowException extends HttpException {
    public function __construct() {
        parent::__construct(403, 'You cannot follow yourself.');
    }
}
```

- `InvalidCredentialsException` is thrown on `/auth/login` when the email doesn't exist **or** the password hash check fails (don't leak which one — same message either way).
- `SelfFollowException` is thrown by **both** `/users/{user}/follow` and `/users/{user}/unfollow` when target = self.

## 6. File storage

- Disk: `public` everywhere.
- Post image path: `$image->store('posts', 'public')` → stored as `posts/<random>.<ext>`.
- Avatar path: `$file->store('avatars', 'public')` → `avatars/<random>.<ext>`.
- The DB stores the **relative path** (`avatar_url`, `image_url` columns are paths, not URLs).
- Resources serialize them as **absolute URLs** via `Storage::disk('public')->url($path)`.
- On avatar upload: store new file → update DB in a transaction → delete previous file. If the DB write throws, roll back by deleting the just-stored new file.
- On post creation: store image → create row in transaction; on transaction failure, delete the just-stored file.
- On post deletion: delete the row, then delete the file (best-effort — failure to delete the file should not bubble up as an error).

Helper: a `DeletesPublicFiles` trait wraps `Storage::disk('public')->delete($path)` in a try/catch so missing files don't error.

## 7. Service layer (business logic)

### `UserService`

- **`findByUsername(string $username): User`** — `User::where('username', $username)->firstOrFail()` → 404 on miss.
- **`updateProfile(User, array): User`** — `$user->fill($data)->save()` then `refresh()`.
- **`uploadAvatar(User, UploadedFile): User`** — see §6.
- **`search(string $q, int $perPage = 15)`**:
  ```php
  User::query()
      ->where(fn($w) => $w->where('username', 'like', "%{$q}%")->orWhere('name', 'like', "%{$q}%"))
      ->orderBy('username')
      ->paginate($perPage);
  ```
- **`suggestions(User $viewer, int $perPage = 20)`**:
  ```php
  User::query()
      ->whereKeyNot($viewer->getKey())
      ->orderBy('username')
      ->paginate($perPage);
  ```
  **Note:** does NOT filter out already-followed users. Match this exactly — the OpenAPI says "excluding the current user" and that's the only exclusion.

### `FollowService`

- `follow(follower, target)` and `unfollow(follower, target)` both call a private `rejectSelfTarget` first → throws `SelfFollowException` if `follower.id === target.id`.
- `follow()`: `$follower->following()->syncWithoutDetaching([$target->id])` (idempotent).
- `unfollow()`: `$follower->following()->detach($target->id)` (idempotent — detach of non-row is a no-op).
- `isFollowing(follower, target)`: `$follower->following()->whereKey($target->id)->exists()`.
- `followers(user, perPage=20)`: `$user->followers()->orderBy('follows.created_at', 'desc')->paginate($perPage)`.
- `following(user, perPage=20)`: same with `following()`.

The pivot ordering uses the `follows.created_at` column explicitly to avoid ambiguous-column errors.

### `LikeService`

- `like(user, post)`:
  ```php
  DB::transaction(function () use ($user, $post) {
      $user->likedPosts()->syncWithoutDetaching([$post->id]);
      return $post->likes()->count();
  });
  ```
- `unlike(user, post)`: same pattern with `detach`.
- Both return the **post-operation** likes_count (used by the controller in the `likes_count` field of the response — see OpenAPI's like/unlike responses).
- `likers(post, perPage=20)`: `$post->likers()->orderBy('likes.created_at', 'desc')->paginate($perPage)`.

### `FeedService::feed(User $user, int $perPage = 15)`

The exact query — match it:

```php
Post::query()
    ->select('posts.*')
    ->join('follows', 'follows.following_id', '=', 'posts.user_id')
    ->where('follows.follower_id', $user->getKey())
    ->withSummary($user)
    ->orderByDesc('posts.created_at')
    ->orderByDesc('posts.id')
    ->cursorPaginate($perPage);
```

- The viewer's **own** posts are NOT in their feed (no self-follow → no JOIN match).
- Sort uses `(created_at DESC, id DESC)` so cursor pagination is stable across same-second posts.

### `PostService`

- `create(user, image, ?caption)`: store image (§6) → `Post::forceFill(['image_url' => $path])` (the caption is fillable; image_url isn't, hence forceFill) → return with summary.
- `find(id, ?viewer)`: `Post::query()->withSummary($viewer)->findOrFail($id)`.
- `update(post, data, ?viewer)`: `fill($data)->save()` then reload summary.
- `delete(post)`: capture `$post->getRawOriginal('image_url')` first, delete row, then delete file.
- `listByUser(user, ?viewer, perPage=15)`:
  ```php
  $user->posts()
      ->withSummary($viewer)
      ->orderByDesc('created_at')
      ->orderByDesc('id')
      ->paginate($perPage);
  ```

### `CommentService`

- `create(user, post, body)`: `$post->comments()->create(['user_id' => $user->id, 'body' => $body])` then `load('user')`.
- `update(comment, data)`: `fill->save` then `load('user')`.
- `delete(comment)`: `$comment->delete()`.
- `listByPost(post, perPage=20)`:
  ```php
  $post->comments()
      ->with('user')
      ->orderByDesc('created_at')
      ->orderByDesc('id')
      ->paginate($perPage);
  ```

## 8. `Post::withSummary` local scope

Mandatory — feed, single post, post listings all rely on it. Adds three derived attributes:

```php
public function scopeWithSummary(Builder $q, ?User $viewer): Builder
{
    $q->withCount(['likes', 'comments']);  // → likes_count, comments_count

    if ($viewer !== null) {
        $q->withExists([
            'likes as liked_by_me' => fn($w) => $w->where('user_id', $viewer->getKey()),
        ]);
    }

    return $q;
}
```

When `$viewer === null`, `liked_by_me` is absent from the row; the resource should default it to `false` (or omit it — frontend treats both as not-liked).

## 9. JSON serialization (API Resources)

### Wrapping behavior — read carefully

OpenAPI's `PostResponse` and `CommentResponse` schemas declare `{"data": Post}` envelopes. `User`-returning endpoints declare a bare `User`. Implement accordingly:

- `PostResource` and `CommentResource`: **default Laravel wrapping** (`{"data": {...}}`).
- `UserResource`: **call `static::$wrap = null`** (in a service provider's `boot()` or via `UserResource::withoutWrapping()`) so single-user responses are unwrapped.
- Paginated collections: Laravel's `ResourceCollection` envelope (`{data, links, meta}`) for length-aware, `{data, meta}` for cursor.

### `UserResource` shape

```json
{
  "id": 1,
  "name": "...",
  "username": "...",
  "email": "..." | omitted,
  "bio": null | "...",
  "avatar_url": null | "https://.../storage/avatars/...",
  "created_at": "...",
  "updated_at": "..."
}
```

`email` is included **only** when the resource is being serialized for the user themselves — i.e. the authenticated request user is the same row. Implementation pattern:

```php
'email' => $this->when(
    $request->user()?->is($this->resource),
    $this->email
),
```

`avatar_url` resolves the relative path: `$this->avatar_url ? Storage::disk('public')->url($this->avatar_url) : null`.

### `PostResource` shape

```json
{
  "id": 1,
  "user_id": 1,
  "image_url": "https://.../storage/posts/...",   // absolute
  "caption": null | "...",
  "created_at": "...",
  "updated_at": "...",
  "likes_count": 0,
  "comments_count": 0,
  "liked_by_me": false,
  "user": { ...UserResource (or array) }
}
```

`image_url`: always absolute via `Storage::disk('public')->url($this->image_url)`.

### `CommentResource` shape

```json
{
  "id": 1,
  "user_id": 1,
  "post_id": 1,
  "body": "...",
  "created_at": "...",
  "updated_at": "...",
  "user": { ...UserResource (or array) }
}
```

### `UserWithPivot` (followers/following/likers lists)

When the user comes through a `belongsToMany` query (`followers`, `following`, `likers`), Laravel attaches a `pivot` object. Don't strip it — the OpenAPI `UserWithPivot` schema expects it.

## 10. Pagination defaults

The reference uses these defaults (overridable via `?per_page=`):

| Endpoint                      | Default | Type   |
|-------------------------------|---------|--------|
| `GET /users/search`           | 15      | length |
| `GET /users/suggestions`      | 20      | length |
| `GET /users/{user}/posts`     | 15      | length |
| `GET /users/{user}/followers` | 20      | length |
| `GET /users/{user}/following` | 20      | length |
| `GET /posts/{post}/likes`     | 20      | length |
| `GET /posts/{post}/comments`  | 20      | length |
| `GET /feed`                   | 15      | cursor |

Only `GET /users/search` validates `per_page` (1–50). Other endpoints pass it directly to `paginate()`/`cursorPaginate()`.

## 11. Models — relationships

### `User`

Extends `Authenticatable`, uses `HasApiTokens`, `Notifiable`.

- `posts()` → hasMany(Post)
- `comments()` → hasMany(Comment)
- `likedPosts()` → belongsToMany(Post, 'likes')->withTimestamps()
- `following()` → belongsToMany(User, 'follows', 'follower_id', 'following_id')->withTimestamps()
- `followers()` → belongsToMany(User, 'follows', 'following_id', 'follower_id')->withTimestamps()

`$hidden`: `['password', 'remember_token']`. `$casts`: `['password' => 'hashed', 'email_verified_at' => 'datetime']`.

`$fillable`: `['name', 'username', 'email', 'password', 'bio']`. `avatar_url` is **not** fillable (assigned via `forceFill` in the service).

### `Post`

- `user()` → belongsTo(User)
- `comments()` → hasMany(Comment)
- `likes()` → hasMany(Like)
- `likers()` → belongsToMany(User, 'likes')->withTimestamps()
- `$fillable`: `['caption']` only. `image_url` assigned via `forceFill`.
- Local scope: `withSummary` (see §8).

### `Comment`

- `user()` → belongsTo(User)
- `post()` → belongsTo(Post)
- `$fillable`: `['user_id', 'body']`.

### `Like` (optional pivot model)

- `user()` → belongsTo(User)
- `post()` → belongsTo(Post)
- `$fillable`: `['user_id', 'post_id']`.

## 12. Route binding

Route parameters use Laravel's implicit binding:

- `{user}` → `User` by `id` (numeric).
- `{post}` → `Post` by `id`.
- `{comment}` → `Comment` by `id`.
- `{username}` → resolved manually (`UserService::findByUsername`) — **do not** use route-model binding here.

A miss on any of these returns 404 via `firstOrFail`/`findOrFail`.

## 13. CORS for `/storage/*`

Frontend dev hosts must be able to fetch uploaded images cross-origin. The `docker/Caddyfile` handles this (no Laravel CORS middleware needed) — it adds:

- `Access-Control-Allow-Origin` for `localhost:3000|5173|8080` (regex match).
- `Cross-Origin-Resource-Policy: cross-origin`.
- 204 on OPTIONS preflight.

If you serve via `php artisan serve` instead of Docker, replicate this with a CORS package or it'll break image rendering in the frontend.

## 14. Laravel CORS for the API itself

The frontend (Vite/Next/etc.) calls `/api/*` from a different origin in dev. Configure `config/cors.php` so:

- `paths`: `['api/*', 'sanctum/csrf-cookie']`
- `allowed_origins` (or pattern): your dev hosts.
- `supports_credentials`: false (Sanctum personal access tokens use bearer auth, not cookies).

## 15. What the OpenAPI doesn't fully capture (and you should re-check)

- The **`per_page` clamping note** in OpenAPI applies only to `/users/search`. Other endpoints accept any positive integer.
- The **idempotency** of follow/unfollow/like/unlike means a duplicate call returns 200 (not 409). Match the message strings exactly: `"Followed."`, `"Unfollowed."`, `"Liked."`, `"Unliked."`.
- Self-follow attempts return 403 from BOTH POST and DELETE.
- Validation responses use Laravel's default 422 body (`{"message": "...", "errors": {"field": ["msg", ...]}}`) — already in OpenAPI's `ValidationErrorBody`.
