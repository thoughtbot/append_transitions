# Changelog

All notable changes to this project are documented in this file. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-27

Initial release.

### Added

- `AppendTransitions::HasCurrent`, which adds `current_*`,
  `transition_*` and `with_current_*` to a model whose state lives in
  an append-only table.
- Transitions validated against an initial state and allowed
  transitions, and serialized with a row lock on the parent.
- `with_current_*`, which loads each record's current state in the
  same query through a `LEFT JOIN LATERAL`.
- A check for the index lookups read through, configurable to warn or
  raise.
- The `append_transitions:state` generator, which creates the state
  table, its index and a read-only model.

[Unreleased]: https://github.com/thoughtbot/append_transitions/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/thoughtbot/append_transitions/releases/tag/v0.1.0
