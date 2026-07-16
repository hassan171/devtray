/// dio support for `debug_overlay`.
///
/// Add the interceptor **last**, so it sees the final headers the interceptors
/// before it set:
///
/// ```dart
/// final dio = Dio()..interceptors.add(DebugDioInterceptor());
/// ```
///
/// Every request through that client then shows up on the overlay's Network
/// page, and mock rules intercept it.
///
/// This lives outside the core so an app that doesn't use dio never compiles it
/// — see MIGRATION_PLAN.md.
library;

export 'src/dio_adapter.dart';
