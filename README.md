# AppendTransitions

[![CI](https://github.com/thoughtbot/append_transitions/actions/workflows/ci.yml/badge.svg)](https://github.com/thoughtbot/append_transitions/actions/workflows/ci.yml)

AppendTransitions implements a better default for state transitions
in ActiveRecord: each transition is a new row, and PostgreSQL does the
work of keeping that efficient.

## Why AppendTransitions?

AppendTransitions packages a practice: store each state transition
as its own row instead of overwriting a column.

Most applications track state with a mutable string column:

```
users
  id
  status
```

That works until someone asks when a user was approved, or how
long they waited. Each update overwrites the previous state, and you
can't backfill history you never recorded. Adding a separate history
table later doesn't fully fix it. Now the column and the history
have to be kept in sync, and they can drift apart.

With AppendTransitions, the state lives in its own table, and each
transition adds a row:

```
users
  id

user_statuses
  id
  user_id
  status
  created_at
```

`user_statuses` is both the history and the source of truth: its
most recent row is the current state. PostgreSQL keeps this
efficient:

- **Reading the current state is fast.** Only the latest row per
  record is fetched, through an index, no matter how long the history
  grows. It loads as a regular ActiveRecord object, for one record or
  many, without N+1 queries. For many records, this uses a
  `LEFT JOIN LATERAL`.
- **Transitions stay consistent.** Each transition is checked against
  the allowed transitions, and concurrent transitions for the same
  record run one at a time, so simultaneous requests can't leave a
  record in an invalid state. This uses `SELECT ... FOR UPDATE` on
  the user's row.

AppendTransitions also comes with the most common functionality
you'd need from a state machine: allowed transitions are enforced,
and concurrent transitions can't corrupt the state. With it, you may
not need a state machine gem at all. AppendTransitions leaves out
callbacks, guards, events and DSLs, has no dependencies beyond
ActiveRecord, and no monkey patches: you get a few methods on your
model and plain ActiveRecord objects back.

Instead of hiding side effects in callbacks on the state, keep them
in the code that requests the transition, such as a service object.
When they need to run inside the lock, pass a block to
`transition_status`.

For the reasoning and benchmarks behind this design, see
[Modeling State Transitions in Postgres][modeling-post] and
[Inserting State Transitions in Postgres][inserting-post].

[modeling-post]: https://thoughtbot.com/blog/modeling-state-transitions-in-postgres
[inserting-post]: https://thoughtbot.com/blog/inserting-state-transitions-in-postgres

## When to use something else

Appending a row per transition fits states that change a handful of
times over a record's life and whose history matters, like most
business workflows. Consider something else when:

- **The value changes constantly.** For things like chat presence
  or a progress percentage, every change adds a row and an index
  entry that nobody will query. A column is simpler. If you do need
  that history at high volume, like device telemetry, use a store
  built for time series.
- **You only need an audit trail.** For debugging or compliance
  across many models, a generic tool like
  [PaperTrail](https://github.com/paper-trail-gem/paper_trail) tracks
  changes everywhere with less setup. It stores changes as serialized
  data, which is fine for an audit log but awkward to query, so it
  complements state history rather than replacing it.

## Requirements

- PostgreSQL
- Ruby 3.2+
- ActiveRecord 7.0+

The generator needs Rails; the gem itself only depends on
ActiveRecord.

Other databases aren't supported (see [Limitations](#limitations)).

## Installation

Add to your Gemfile:

```ruby
gem "append_transitions"
```

Then run:

```bash
bundle install
```

## Usage

### The state table

The examples track a user's status, but anything with a lifecycle
works, like an order's fulfillment or a document's review. The model
whose state is tracked, `User` here, is the *parent*.

```bash
bin/rails generate append_transitions:state User status
```

This creates a migration (and the model, below):

```ruby
class CreateUserStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :user_statuses do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :status, null: false
      t.timestamps
    end

    add_index :user_statuses, [:user_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      include: :status
  end
end
```

The index lets PostgreSQL find each user's latest status without
scanning the table, and `include` (ActiveRecord 7.1+) lets it answer
from the index alone.

Together, the two arguments, `User` and `status`, form the table
name, `user_statuses`, and the state model, `UserStatus`.

By default, the state column is named `status`, so our first command
could be written with an explicit `--state-column` option:

```bash
bin/rails generate append_transitions:state User status --state-column=status
```

You can also use a different name:

```bash
# DocumentReview model, document_reviews table with a stage column,
# and current_review on Document
bin/rails generate append_transitions:state Document review --state-column=stage
```

The migration follows your app's primary key type (`bigint` unless
you've configured another), which you can change with
`--primary-key-type`, just like in Rails. You can also pass
`--database`, which puts the migration in that database and makes
the model inherit from its abstract class (e.g. `AnimalsRecord`),
creating the class if it's missing.

A namespaced parent gets a namespaced model and table:

```bash
# Admin::UserStatus model and admin_user_statuses table
bin/rails generate append_transitions:state Admin::User status
```

If you write the migration yourself and leave out the index, the
[missing index check](#missing-index-check) warns you the first
time the state is read and tells you which index to add.

### The models

The generator also creates the state model:

```ruby
class UserStatus < ApplicationRecord
  belongs_to :user

  def readonly? = super || (persisted? && !destroyed_by_association)
end
```

Rows are never updated or deleted. `readonly?` makes persisted
records read-only so that `update!` and `destroy` raise
`ActiveRecord::ReadOnlyRecord`. Each part of the method has a role:

- `persisted?` still lets new rows be created.
- `!destroyed_by_association` lets the parent destroy its rows
  through `has_many ..., dependent: :destroy`.
- `super` keeps `readonly!` working.

> [!WARNING]
> The check runs on individual records, so bulk methods like
> `update_all` and `delete_all` skip it.

The generator doesn't change the parent model. It prints an
`include AppendTransitions::HasCurrent` to paste into it, with
placeholder states to replace with your own, for example:

```ruby
class User < ApplicationRecord
  include AppendTransitions::HasCurrent.new(
    :status,
    class_name: "UserStatus",
    initial_state: :pending,
    transitions: {
      pending: [:approved, :denied],
      denied: :pending
    }
  )
end
```

`initial_state` is the only state a user without any rows can
transition to. Each key in `transitions` lists the states it can
move to.

### Reading the current state

```ruby
user.current_status        # => #<UserStatus status: "approved">
user.current_status.status # => "approved"
```

`current_status` returns `nil` for a user without any rows. The
result is cached on the record, like an association. `reload` and
`transition_status` (see [Transitioning](#transitioning)) clear it.

States are declared as symbols, but the column holds strings, so
`status` reads back as `"approved"`. `transition_status` accepts
either, as do the keys and values in `transitions`.

### Querying many records

`with_current_status` loads each user's current status in the same
query, so iterating doesn't trigger extra queries:

```ruby
User.with_current_status.each do |user|
  user.current_status # no extra query
end
```

Filter by the current status with a hash, as with any joined table:

```ruby
User.with_current_status.where(current_status: {status: "approved"})
```

It returns a regular relation, so it chains with `where`, `count`,
`pluck`, `find_each` and friends.

> [!WARNING]
> The current status loads from columns `with_current_status` adds
> to the query. Replacing them, e.g. with `reselect`, brings back
> N+1 queries: `current_status` queries once per record instead.

### Transitioning

```ruby
user.transition_status(:pending)  # => #<UserStatus status: "pending">
user.transition_status(:approved) # => #<UserStatus status: "approved">
user.transition_status(:pending)
# => raises AppendTransitions::InvalidTransition:
#    Cannot transition from approved to pending
```

`transition_status` locks the user's row, reads the current status,
checks the transition, and inserts the new row, all in one
transaction. A concurrent transition for the same user waits for the
lock, then sees the updated status. The new row's `created_at` is
always after the current one's, even if another server's clock is
ahead. The user isn't reloaded, so unsaved changes on it are kept.

Pass a block to run code inside the same transaction, after the
insert. The block receives the new record. If the transition is
invalid, the block doesn't run. If the block raises, the insert is
rolled back:

```ruby
user.transition_status(:approved) do |status|
  Notification.create!(user:, message: "Approved at #{status.created_at}")
end

UserMailer.approved(user).deliver_later
```

Send emails and other side effects that can't be rolled back after
the call, so they only happen once the transition is committed.
If two requests approve the same user at once, the second waits for
the lock, finds the user already approved and raises
`AppendTransitions::InvalidTransition`, so the email only goes out
once.

### Options

| Option          | Default                          | Description                                      |
|-----------------|----------------------------------|--------------------------------------------------|
| `class_name`    | (required)                       | The state model                                  |
| `initial_state` | (required)                       | The first state a record can transition to       |
| `transitions`   | `{}`                             | Allowed transitions, from a state to one or many |
| `foreign_key`   | inferred, e.g. `user_id`         | The state table's column pointing to the parent  |
| `state_column`  | `:status`                        | The state table's column holding the state       |
| `order`         | `{created_at: :desc, id: :desc}` | The `ORDER BY` that puts the current row first   |

The first argument to `HasCurrent.new` names the methods it adds
(the generator fills it in from its own second argument). `:status`
gives `current_status`, `transition_status` and
`with_current_status`, so a model can track more than one state.
Here, the state lives in a `stage` column:

```ruby
class Document < ApplicationRecord
  include AppendTransitions::HasCurrent.new(
    :review,
    class_name: "DocumentReview",
    state_column: :stage,
    initial_state: :requested,
    transitions: {requested: [:accepted, :rejected]}
  )
end

# Example usage
document = Document.find(27)
document.transition_review(:requested)
puts document.current_review.stage # prints "requested"

Document.with_current_review.where(current_review: {stage: "requested"}).each do |doc|
  puts doc.current_review.stage # no extra query
end
```

The default `order` configuration, which the example above leaves
out, breaks ties on `created_at` with `id`, since `created_at` isn't
unique. `order` must be a hash of columns to directions, since the
recommended index is built from it. If you change `order`, keep the
index in the same order (edit the generated migration).

### Missing index check

The first time `current_*` or `with_current_*` runs, AppendTransitions
checks that the state table has an index starting with the foreign
key, followed by the `order` columns (`user_id, created_at, id` by
default). Without one, lookups of the current state, including the
one `transition_*` makes, slow down as the history grows. By default
it prints a warning with the `add_index` call to put in a migration:

```ruby
add_index :user_statuses, [:user_id, :created_at, :id],
  order: {created_at: :desc, id: :desc}, include: :status
```

The check skips partial and expression indexes, and doesn't look at
sort directions or `include`. PostgreSQL can read an index in either
direction, and an index without `include` still finds the latest
row, only with an extra read of the table.

To raise instead of warning:

```ruby
# config/initializers/append_transitions.rb
AppendTransitions.configure do |config|
  config.on_missing_index = :raise
end
```

## Limitations

- **PostgreSQL only.** AppendTransitions is only tested on
  PostgreSQL. On SQLite, `with_current_status` fails with an SQL
  syntax error. `current_status` and `transition_status` still run,
  but SQLite has no `FOR UPDATE` row locks, so concurrent transitions
  aren't serialized there.
- **Extra attributes on the parent.** `with_current_status` selects
  the state columns as `current_status_id`, `current_status_status`
  and so on. They show up in the parent's `attributes`, `as_json` and
  `inspect`. ActiveRecord has no public way to hide selected columns.
- **Writes that bypass `transition_*`.** Creating rows directly, such
  as `UserStatus.create!`, skips both the lock and the transition
  check. Validation lives in the application, not the database.
- **Changes from other processes.** Like an association,
  `current_status` is cached per record. A transition made elsewhere
  isn't visible until you `reload`.
- **Composite primary keys** on the parent aren't supported.
- **Separate databases.** The parent and the state table must share a
  database. Otherwise the lock and the insert run in separate
  transactions, so a failing block doesn't roll back the insert.

## Stability

AppendTransitions is intentionally minimal. It builds on long-standing
ActiveRecord and PostgreSQL features, so we expect it to change
rarely, and mostly in additive ways.

One part relies on an ActiveRecord internal: `with_current_*`
hydrates records by reading `@records` on the relation, as the
Goldiloader and Bullet gems do. CI runs every supported ActiveRecord
version to catch changes there.

## Development

After checking out the repo, run `bin/setup` to install
dependencies. The tests need a local PostgreSQL database named
`append_transitions_test`:

```bash
createdb append_transitions_test
bundle exec rake
```

`bundle exec rake` runs the tests and the linter. To test against
another ActiveRecord version, point `BUNDLE_GEMFILE` at one of the
files in `gemfiles/`:

```bash
BUNDLE_GEMFILE=gemfiles/activerecord_7.0.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/activerecord_7.0.gemfile bundle exec rake test
```

## Contributing

See the [CONTRIBUTING] document.
Thank you, [contributors]!

[CONTRIBUTING]: CONTRIBUTING.md
[contributors]: https://github.com/thoughtbot/append_transitions/graphs/contributors

## License

AppendTransitions is Copyright (c) thoughtbot, inc.
It is free software, and may be redistributed
under the terms specified in the [LICENSE] file.

[LICENSE]: /LICENSE

## About thoughtbot

![thoughtbot](https://thoughtbot.com/thoughtbot-logo-for-readmes.svg)

This repo is maintained and funded by thoughtbot, inc.
The names and logos for thoughtbot are trademarks of thoughtbot, inc.

We love open source software!
See [our other projects][community].
We are [available for hire][hire].

[community]: https://thoughtbot.com/community?utm_source=github
[hire]: https://thoughtbot.com/hire-us?utm_source=github
