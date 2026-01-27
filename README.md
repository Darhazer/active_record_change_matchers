# active_record_change_matchers

RSpec matchers that assert **exactly which** ActiveRecord records were created inside a block—by count, model, attributes, and association scope.

This is a hard fork of [active_record_block_matchers](https://github.com/nwallace/active_record_block_matchers). See [CHANGELOG](CHANGELOG.md) for changes since the original.

---

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Matcher reference](#matcher-reference)
  - [Summary](#matcher-summary)
  - [create_a / create_a_new](#create_a--create_a_new)
  - [create / create_records](#create--create_records)
  - [create_associated](#create_associated)
- [Record retrieval strategies](#record-retrieval-strategies)
- [Configuration](#configuration)
- [Tips and gotchas](#tips-and-gotchas)
- [Development](#development)
- [Contributing](#contributing)

---

## Requirements

- **Ruby** ≥ 3.3
- **Rails** ≥ 7 (ActiveRecord)
- **RSpec** ≥ 3 (rspec-expectations)

---

## Installation

Add to your Gemfile:

```ruby
gem 'active_record_change_matchers'
```

Then:

```bash
bundle install
```

---

## Quick start

```ruby
# One record of a given model
expect { post :create, params: { user: { name: "Bob" } } }
  .to create_a(User)
  .with_attributes(name: "bob")   # e.g. after downcasing in a callback

# Several models, exact counts
expect { sign_up!("bob", "secret") }
  .to create(User => 1, Profile => 1)
  .with_attributes(
    User    => [{ name: "bob" }],
    Profile => [{ avatar_url: Profile.default_avatar_url }]
  )
  .which { |records|
    user = records[User].first
    profile = records[Profile].first
    expect(user.profile).to eq profile
  }

# New records only within an association
expect { create_items }
  .to create_associated(record.items => 2)
  .with_attributes([{ content: "item1" }, { content: "item2" }])
```

---

## Matcher reference

### Matcher summary

| Matcher              | Aliases           | Use when you want to assert…                          |
|----------------------|-------------------|--------------------------------------------------------|
| `create_a(Model)`    | `create_an`, `create_a_new` | Exactly one new record of that model               |
| `create(Model => n, …)` | `create_records`  | Exact counts of new records per model                 |
| `create_associated(scope)` | —                | New records only within that association (e.g. `user.posts`) |

All support chaining:

- **`.with_attributes(...)`** – attribute (or computed) expectations; works with [composable matchers](https://rspec.info/features/3-13/rspec-expectations/composing-matchers/).
- **`.which { |record_or_hash| ... }`** – extra expectations in a block (e.g. associations, side effects).
- **`.and_return_it`** / **`.and_return_them`** – that the block’s return value is the created record(s).

`create_a` also supports **`.which_is_expected_to(matcher)`** for a single composable matcher on the new record.

---

### create_a / create_a_new

Asserts the block creates **exactly one** new record of the given model. Ignores records that already existed before the block ran.

**Minimal:**

```ruby
expect { User.create! }.to create_a(User)
```

**With attributes** (DB columns or any reader, e.g. from callbacks):

```ruby
expect { User.create!(username: "BOB") }
  .to create_a(User)
  .with_attributes(username: "bob")
```

**With composable matchers:**

```ruby
expect { User.create!(username: "bob") }
  .to create_a(User)
  .with_attributes(username: a_string_starting_with("b"))
```

**With a matcher (`.which_is_expected_to`):**

```ruby
expect { User.create!(username: "BOB", password: "secret") }
  .to create_a(User)
  .which_is_expected_to(
    have_attributes(encrypted_password: be_present)
      .and(eq(Auth.authenticate("bob", "secret")))
  )
```

**With a block (`.which`)** when you need full control:

```ruby
expect { User.create!(username: "BOB", password: "secret") }
  .to create_a(User)
  .which { |user|
    expect(user.encrypted_password).to be_present
    expect(Auth.authenticate("bob", "secret")).to eq user
  }
```

**That the block returns the new record (`.and_return_it`):**

```ruby
expect { create_user(name: "bob") }
  .to create_a(User)
  .with_attributes(name: "bob")
  .and_return_it
```

**Negated:** use `.not_to create_a(User)` to assert the block did *not* create exactly one `User` (e.g. created zero or more than one).

**Failure cases:**

- Creates 0 → *"the block should have created 1 User, but created 0"*
- Creates 2+ → *"the block should have created 1 User, but created 2"*
- Attribute mismatch → *"Expected :username to be \"bob\", but was \"BOB\""*
- `.which` or `.which_is_expected_to` fail → their messages are shown

---

### create / create_records

Asserts the block creates **exactly** the given counts per model. Argument is a hash: `Model => count`.

**Minimal:**

```ruby
expect { User.create!; User.create!; Profile.create! }
  .to create(User => 2, Profile => 1)
```

**With attributes:** provide one hash per created record. Keys are model classes; values are arrays of attribute hashes. Order of hashes need not match creation order.

```ruby
expect { User.create!(username: "bob"); User.create!(username: "rhonda") }
  .to create(User => 2)
  .with_attributes(
    User => [{ username: "rhonda" }, { username: "bob" }]
  )
```

You must supply **as many attribute hashes as the expected count** for that model. Fewer raises an argument error; you can use empty hashes for records you don’t care to constrain:

```ruby
.with_attributes(User => [{ username: "bob" }, {}])
```

**With a block (`.which`):** the block receives a hash `Model => [records]`:

```ruby
expect { sign_up!("bob", "secret") }
  .to create(User => 1, Profile => 1)
  .with_attributes(
    User    => [{ username: "bob" }],
    Profile => [{ avatar_url: Profile.default_avatar_url }]
  )
  .which { |records|
    user = records[User].first
    profile = records[Profile].first
    expect(user.profile).to eq profile
  }
```

**That the block returns all created records (`.and_return_them`):** the matcher checks that every created record appears in the block’s return value (array, relation, or any enumerable).

```ruby
expect { [User.create!, User.create!] }.to create(User => 2).and_return_them
```

**Negated:** `.not_to create(User => 2)` asserts the block did not create exactly two `User`s.

---

### create_associated

Asserts that new record(s) were created **within the given association scope(s)** only. The model is inferred from the scope (e.g. `user.posts` → `Post`). Other associations and pre-existing records are ignored.

**Scope form (expects exactly one new record in that association):**

```ruby
expect { user.posts.create!(title: "Hi") }.to create_associated(user.posts)
```

**Hash form (expects the given count per scope):**

```ruby
expect {
  user.posts.create!(title: "A")
  user.posts.create!(title: "B")
}.to create_associated(user.posts => 2)
```

**With attributes**

- One scope, one record: pass a single hash.
- One scope, many records: pass an array of hashes.
- Multiple scopes: pass a hash keyed by scope, each value an array of attribute hashes.

```ruby
# One record, single hash
expect { user.posts.create!(title: "Hi") }
  .to create_associated(user.posts)
  .with_attributes(title: "Hi")

# One scope, multiple records
expect { add_two_posts }
  .to create_associated(user.posts => 2)
  .with_attributes([{ title: "First" }, { title: "Second" }])

# Multiple scopes
expect { create_mine_and_theirs }
  .to create_associated(user_a.posts => 1, user_b.posts => 1)
  .with_attributes(
    user_a.posts => [{ title: "a" }],
    user_b.posts => [{ title: "b" }]
  )
```

**With `.which`:** the block receives a hash **model class => records** (same shape as `create` / `create_records`):

```ruby
expect { user.posts.create!(title: "x") }
  .to create_associated(user.posts)
  .which { |records_by_klass|
    expect(records_by_klass[Post].first.title).to eq "x"
  }
```

**Return value:**

- Use **`.and_return_it`** only when expecting **exactly one** record (single scope, count 1). It asserts the block returns that record.
- Use **`.and_return_them`** when expecting multiple records; it asserts the block’s return value contains all created records.

Using `.and_return_it` with multiple records (e.g. `create_associated(scope => 2).and_return_it`) raises `ArgumentError`.

**Failure cases:**

- No records in scope → *"The block should have created 1 Post within the scope, but created 0."*
- Records created in a *different* association (or by another owner) are not counted—you’ll get “created 0” if the wrong scope was used.
- Wrong count or attribute mismatch produces messages similar to `create` / `create_records`.

---

## Record retrieval strategies

The matchers need to know which rows were “new” after the block. Two strategies are built in:

| Strategy    | How it finds new records | Default | When to use it |
|-------------|--------------------------|----------|-----------------|
| **`:id`**   | Compares max primary key before/after the block | ✓       | Tables with auto-increment integer PKs (default). |
| **`:timestamp`** | Compares `created_at` (or configured column) before/after; supports frozen time | — | Non-integer PKs or no `id`. |

**`:id`** is the default because it doesn’t depend on clock precision or time mocking. Use **`:timestamp`** when you don’t have a monotonic `id` (e.g. UUIDs, legacy schemas).

Strategy can be set globally in [configuration](#configuration) or overridden per expectation:

```ruby
expect { Person.create! }.to create_a(Person, strategy: :timestamp)
```

`create_associated` uses the configured default strategy only (it has no per-call strategy option).

---

## Configuration

Configure column names and default strategy in your RSpec setup (e.g. `spec/rails_helper.rb` or `spec_helper.rb`):

```ruby
ActiveRecordChangeMatchers::Config.configure do |config|
  # Primary key column for :id strategy (default: "id")
  config.id_column_name = "primary_key"

  # Timestamp column for :timestamp strategy (default: "created_at")
  config.created_at_column_name = "created_timestamp"

  # Default strategy: :id or :timestamp (default: :id)
  config.default_strategy = :timestamp
end
```

---

## Tips and gotchas

**Block syntax with `.which`**

Use braces `{ }` for the block passed to `.which`. With `do ... end`, Ruby binds the block to `expect(...).to(...)` instead of `.which`, so the block may never run and the test can falsely pass:

```ruby
# Prefer:
.to create_a(User).which { |user| expect(user.name).to eq "bob" }

# Parsing trap with do/end:
.to create_a(User).which do |user|
  expect(user.name).to eq "bob"   # this block is not passed to .which
end
```

**Composable matchers**

`with_attributes` accepts RSpec composable matchers, which keeps specs readable and failure messages clear:

```ruby
.with_attributes(
  username: a_string_matching(/\A[a-z]+\z/),
  age:      be_between(18, 120)
)
```

**Attributes and virtual/derived values**

`with_attributes` uses `record.public_send(field)` for each key, so you can assert on any public reader—database columns, delegations, or methods (e.g. `full_name` built from `first_name` and `last_name`).

---

## Development

```bash
git clone https://github.com/Darhazer/active_record_change_matchers
cd active_record_change_matchers
bin/setup
bundle exec rspec
```

To install the gem locally:

```bash
bundle exec rake install
```

---

## Contributing

1. Fork the repo.
2. Create a feature branch: `git checkout -b my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push: `git push origin my-feature`
5. Open a Pull Request against this repository.

---

**License:** MIT.  
**Changelog:** [CHANGELOG.md](CHANGELOG.md).
