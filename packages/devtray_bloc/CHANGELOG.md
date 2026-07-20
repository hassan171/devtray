# Changelog

## 0.5.0

No changes of its own. The core folded `DevtrayKillSwitch` and `DevtrayController` into
`Devtray` and reshaped `runDebugApp`'s signature — see its changelog for the migration table.

## 0.4.0

No changes of its own, but the core renamed several public types — see its
changelog for the migration table. Requires `devtray ^0.4.0`.

## 0.3.0

No changes. Versioned in step with the rest of the set, and requires
`devtray ^0.3.0` — see the core's changelog for the new Timeline page.

## 0.2.0

- `onTransition` now checks the kill switch before stashing the pending event. Without it,
  a release build with the observer installed kept taking a strong reference to an event
  object per transition, for a `DevtrayState` that was never going to read them.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
