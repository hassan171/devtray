# Changelog

## 0.2.0

- The observers check the kill switch before resolving a provider's notifier. That
  resolution throws and catches a `NoSuchMethodError` for every plain `Provider` and
  `FutureProvider` — exception construction, with a stack capture, on every provider
  update. A release build should not be paying for it.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
