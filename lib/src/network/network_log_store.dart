import 'package:flutter/foundation.dart';

enum NetworkLogStatus { pending, success, failed }

/// A single captured request/response pair. Transport-agnostic — dio, http and
/// hand-rolled clients all funnel into this shape via [NetworkLogStore].
class NetworkLogEntry {
  final int id;
  final String method;
  final Uri uri;
  final Map<String, dynamic> requestHeaders;
  final Map<String, dynamic> queryParameters;
  final dynamic requestBody;
  final DateTime startedAt;

  int? statusCode;
  Map<String, List<String>> responseHeaders;
  dynamic responseBody;
  String? errorMessage;
  DateTime? completedAt;
  NetworkLogStatus status;

  /// Free-form extra sections rendered as their own detail tabs. Lets a custom
  /// adapter attach transport-specific context (a proxy's generated JS, a
  /// retry trace, a GraphQL operation name…) without changing this class.
  final Map<String, String> extras;

  NetworkLogEntry({
    required this.id,
    required this.method,
    required this.uri,
    required this.requestHeaders,
    required this.queryParameters,
    required this.requestBody,
    required this.startedAt,
    this.statusCode,
    this.responseHeaders = const {},
    this.responseBody,
    this.errorMessage,
    this.completedAt,
    this.status = NetworkLogStatus.pending,
    Map<String, String>? extras,
  }) : extras = extras ?? {};

  Duration? get duration => completedAt?.difference(startedAt);

  String? get responseBodyString {
    final body = responseBody;
    if (body == null) return null;
    return body is String ? body : body.toString();
  }

  /// True when the response looks like HTML — by `content-type` header, or by
  /// sniffing the start of the body (servers don't always set the header).
  bool get isHtmlResponse {
    final contentType = responseHeaders.entries
        .firstWhere((e) => e.key.toLowerCase() == 'content-type', orElse: () => const MapEntry('', <String>[]))
        .value
        .join(',')
        .toLowerCase();
    if (contentType.contains('text/html')) return true;

    final body = responseBodyString;
    if (body == null) return false;
    final trimmed = body.trimLeft().toLowerCase();
    return trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html') || (trimmed.startsWith('<') && trimmed.contains('</html>'));
  }
}

/// In-memory ring buffer of captured requests, backed by a [ValueNotifier] so
/// the network page rebuilds on every change.
///
/// Adapters ([DebugDioInterceptor], [DebugHttpClient]) drive this, but it's
/// public so any client can be wired up by hand:
///
/// ```dart
/// final entry = NetworkLogStore.instance.add(method: 'GET', uri: uri, ...);
/// // ...
/// NetworkLogStore.instance.complete(entry.id, statusCode: 200, status: NetworkLogStatus.success);
/// ```
class NetworkLogStore {
  NetworkLogStore._();
  static final NetworkLogStore instance = NetworkLogStore._();

  /// Oldest entries are dropped past this cap. Tune before wiring up a client.
  int maxEntries = 500;

  /// Requests whose URL contains any of these substrings are never recorded.
  /// Use it to keep high-frequency background traffic (health polls, crash
  /// reporting) out of the list.
  final List<String> excludedUrlPatterns = [];

  final List<NetworkLogEntry> _entries = [];
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  int _nextId = 0;

  List<NetworkLogEntry> get entries => List.unmodifiable(_entries);

  bool isExcluded(Uri uri) {
    if (excludedUrlPatterns.isEmpty) return false;
    final s = uri.toString();
    return excludedUrlPatterns.any(s.contains);
  }

  /// Records the start of a request. Returns null when the URL is excluded —
  /// adapters should treat null as "don't track this one".
  NetworkLogEntry? add({
    required String method,
    required Uri uri,
    Map<String, dynamic> requestHeaders = const {},
    Map<String, dynamic> queryParameters = const {},
    dynamic requestBody,
  }) {
    if (isExcluded(uri)) return null;

    final entry = NetworkLogEntry(
      id: _nextId++,
      method: method,
      uri: uri,
      requestHeaders: Map<String, dynamic>.from(requestHeaders),
      queryParameters: Map<String, dynamic>.from(queryParameters),
      requestBody: requestBody,
      startedAt: DateTime.now(),
    );
    _entries.insert(0, entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    tick.value++;
    return entry;
  }

  void complete(
    int id, {
    required NetworkLogStatus status,
    int? statusCode,
    Map<String, List<String>> responseHeaders = const {},
    dynamic responseBody,
    String? errorMessage,
  }) {
    final entry = _byId(id);
    if (entry == null) return;
    entry.statusCode = statusCode;
    entry.responseHeaders = responseHeaders;
    entry.responseBody = responseBody;
    entry.errorMessage = errorMessage;
    entry.completedAt = DateTime.now();
    entry.status = status;
    tick.value++;
  }

  /// Attaches a named extra section to an entry; it becomes its own detail tab.
  void attachExtra(int id, String label, String content) {
    final entry = _byId(id);
    if (entry == null) return;
    entry.extras[label] = content;
    tick.value++;
  }

  void clear() {
    _entries.clear();
    tick.value++;
  }

  NetworkLogEntry? _byId(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}
