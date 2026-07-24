# Changelog

## 0.6.1

No changes of its own. The core added `..capture(bool)` to `configure` — see its changelog.

## 0.6.0

No changes of its own. The core added listener callbacks on everything it captures
(`onError`, `onResponse`, `onScreen`, …) and made ambient context reach network requests —
see its changelog.

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

- Detects double-registration on the same `Dio`. Adding the interceptor twice created two
  entries per request and orphaned the first as permanently pending, spinner running
  forever — and applied mock delays twice over. The duplicate pass now short-circuits.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
