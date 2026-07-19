# Changelog

## 0.2.0

- Large response bodies are no longer decoded into a second full copy in memory. The bytes
  have to be buffered regardless (the stream is drained and replayed to the caller), but
  past 256KB only the head is decoded, with the truncation marked in the logged body.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
