# Changelog

## 0.2.0

- `onTransition` now checks the kill switch before stashing the pending event. Without it,
  a release build with the observer installed kept taking a strong reference to an event
  object per transition, for a `StateInspector` that was never going to read them.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
