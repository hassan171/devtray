# Changelog

## 0.2.0

- Detects double-registration on the same `Dio`. Adding the interceptor twice created two
  entries per request and orphaned the first as permanently pending, spinner running
  forever — and applied mock delays twice over. The duplicate pass now short-circuits.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
