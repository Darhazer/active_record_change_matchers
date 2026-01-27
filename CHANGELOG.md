# Changelog

## Master (Unreleased)

## 1.1.0 (2026-01-27)
- Add `create_associated(scope)` matcher: verifies creation of new record(s) within an association scope (e.g. `record.items`). Supports `with_attributes`, `which`, `and_return_it`, and `and_return_them`. Model class is inferred from the scope.
- Add `and_return_it` / `and_return_them` modifiers.
- Drop support for Rails < 7

## 1.0.1 (2024-07-03)
- Fix broken timestamp stategy after adding the frozen time support.

## 1.0.0 (2024-07-03)

Hard fork. Changes since the original version:
- Support for frozen time when working with the Timestamp strategy ([original issue](https://github.com/nwallace/active_record_block_matchers/issues/10))
- which_is_expected_to modifier modifier ([original issue](https://github.com/nwallace/active_record_block_matchers/issues/9))