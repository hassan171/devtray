/// `package:http` support for `debug_overlay`.
///
/// Wrap any `Client`:
///
/// ```dart
/// final client = DebugHttpClient(http.Client());
/// await client.get(Uri.parse('https://api.example.com/users'));
/// ```
///
/// Since it's a `BaseClient`, it also drops into anything that accepts one —
/// Supabase, generated OpenAPI clients, and so on. Every request through it
/// shows up on the overlay's Network page, and mock rules intercept it.
///
/// This lives outside the core so an app that doesn't use `package:http` never
/// compiles it — see MIGRATION_PLAN.md.
library;

export 'src/http_adapter.dart';
