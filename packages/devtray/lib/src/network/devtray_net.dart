import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/devtray_facade.dart';
import '../logs/devtray_log.dart';

enum NetworkLogStatus { pending, success, failed }

/// Which failed requests are forwarded to the Logs page (and therefore badge
/// the launcher).
///
/// The default is [all] — every failure is recorded. Pass a narrower mode to
/// [NetworkDebugPage] if the noise gets in the way: [serverAndTransport] skips
/// routine 4xx (a 404 probe, a 401 that triggers a token refresh), which would
/// otherwise keep the badge lit.
enum NetworkErrorReporting {
  /// Nothing is forwarded. Failures still show on the Network page.
  none,

  /// 5xx responses and transport failures (timeout, no connection, bad
  /// certificate — anything with no status code at all).
  serverAndTransport,

  /// Every failed request, including 4xx.
  all,
}

/// A single captured request/response pair. Transport-agnostic — dio, http and
/// hand-rolled clients all funnel into this shape via [DevtrayNet].
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

  /// Method + URL, lowercased, for the search box.
  ///
  /// Cached because `uri.toString()` rebuilds the string from its components
  /// every call, and a search pass touches all 500 entries on every keystroke.
  /// Status code is matched separately — it changes when the request completes.
  String get searchableTarget => _searchableTarget ??= '${method.toLowerCase()} ${uri.toString().toLowerCase()}';
  String? _searchableTarget;

  String? get responseBodyString {
    final body = responseBody;
    if (body == null) return null;
    return body is String ? body : body.toString();
  }

  /// How much of the body the HTML sniff looks at. A document's opening tag is
  /// in the first few bytes; scanning further only costs.
  static const _sniffLimit = 1024;

  /// True when the response looks like HTML — by `content-type` header, or by
  /// sniffing the start of the body (servers don't always set the header).
  ///
  /// Cached: this is read from `build()`, and it used to stringify, trim and
  /// lowercase the *entire* body each time — roughly 3× the body size in
  /// allocations per rebuild, for a multi-MB response.
  ///
  /// Only cached once the request has finished. A pending entry has no body
  /// yet, and caching that `false` would leave the preview button permanently
  /// hidden on a response that turns out to be HTML.
  bool get isHtmlResponse {
    if (status == NetworkLogStatus.pending) return _sniffHtml();
    return _isHtmlResponse ??= _sniffHtml();
  }

  bool? _isHtmlResponse;

  bool _sniffHtml() {
    final contentType = responseHeaders.entries
        .firstWhere((e) => e.key.toLowerCase() == 'content-type', orElse: () => const MapEntry('', <String>[]))
        .value
        .join(',')
        .toLowerCase();
    if (contentType.contains('text/html')) return true;

    final body = responseBody;
    // Only sniff strings. A non-String body means the transport already decoded
    // it into an object, which is by definition not an HTML document — and
    // `toString()`ing it here just to look for '<html' was materialising the
    // whole graph.
    if (body is! String || body.isEmpty) return false;

    final head = (body.length > _sniffLimit ? body.substring(0, _sniffLimit) : body).trimLeft().toLowerCase();
    if (head.startsWith('<!doctype html') || head.startsWith('<html')) return true;
    // A fragment that opens with a tag: still worth previewing. The closing
    // </html> may be past the sniff window, so accept any leading tag.
    return head.startsWith('<') && (head.contains('</html>') || head.contains('<body') || head.contains('<div'));
  }
}

/// A failed request, as reported into the Logs stream.
///
/// Holds the whole [NetworkLogEntry], so the expanded error row can show the
/// URL, status, headers and response body — a transport failure has no
/// meaningful Dart stack trace, so the request itself *is* the diagnostic.
class NetworkError implements Exception {
  final NetworkLogEntry entry;
  const NetworkError(this.entry);

  /// The one-line summary an error row shows.
  @override
  String toString() {
    final code = entry.statusCode;
    final what = code == null ? (entry.errorMessage ?? 'Request failed') : 'HTTP $code';
    return '$what · ${entry.method} ${entry.uri}';
  }
}

/// In-memory ring buffer of captured requests, backed by a [ValueNotifier] so
/// the network page rebuilds on every change.
///
/// Adapters ([DebugDioInterceptor], [DebugHttpClient]) drive this, but it's
/// public so any client can be wired up by hand:
///
/// ```dart
/// final entry = DevtrayNet.instance.add(method: 'GET', uri: uri, ...);
/// // ...
/// DevtrayNet.instance.complete(entry.id, statusCode: 200, status: NetworkLogStatus.success);
/// ```
class DevtrayNet {
  DevtrayNet._() {
    // Flipping the kill switch off must also drop what's already buffered.
    Devtray.addDisableListener(clear);
  }
  static final DevtrayNet instance = DevtrayNet._();

  /// Oldest entries are dropped past this cap. Tune before wiring up a client.
  int maxEntries = 500;

  /// Requests whose URL contains any of these substrings are never recorded.
  /// Use it to keep high-frequency background traffic (health polls, crash
  /// reporting) out of the list.
  final List<String> excludedUrlPatterns = [];

  /// Which failed requests also land in the Logs stream (and badge the
  /// launcher). Defaults to [NetworkErrorReporting.all] — every failure is
  /// recorded. Set it from [NetworkDebugPage]'s `errorReporting` argument, or at
  /// any time from code:
  ///
  /// ```dart
  /// DevtrayNet.instance.errorReporting.value = NetworkErrorReporting.serverAndTransport;
  /// ```
  final ValueNotifier<NetworkErrorReporting> errorReporting = ValueNotifier(NetworkErrorReporting.all);

  /// The largest response body kept, in characters.
  ///
  /// Bodies are retained for the life of the entry, so 500 entries × an
  /// unbounded body is unbounded memory — a handful of large responses (or one
  /// file download) was enough to dwarf the app itself. Oversized bodies are
  /// truncated with a marker naming the original size. Raise it if you need to
  /// inspect big payloads; lower it on a memory-tight device.
  int maxBodyChars = 256 * 1024;

  final List<NetworkLogEntry> _entries = [];

  /// Id → entry, so [complete] and [attachExtra] don't linear-scan 500 entries
  /// on every response.
  final Map<int, NetworkLogEntry> _byIdIndex = {};

  /// A "something changed" signal for the Network page.
  ///
  /// Coalesced, matching [DevtrayLog.tick]: `complete()` is called from inside a
  /// transport interceptor, which can run during any phase of the frame, and a
  /// burst of concurrent requests would otherwise fire a synchronous
  /// notification each. See [CoalescingValueNotifier].
  final CoalescingValueNotifier<int> tick = CoalescingValueNotifier<int>(0);

  int _nextId = 0;

  /// Newest first. An unmodifiable *view*, not a copy — this is read inside a
  /// build, so copying 500 elements per tick and per keystroke was pure waste.
  List<NetworkLogEntry> get entries => UnmodifiableListView(_entries);

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
    // The adapters are installed by the host app, not by the overlay — so in a
    // release build with the interceptor still in place, this would otherwise
    // keep buffering 500 requests (headers, tokens, bodies) that nothing reads.
    if (!Devtray.enabled) return null;
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
    _byIdIndex[entry.id] = entry;
    while (_entries.length > maxEntries) {
      _byIdIndex.remove(_entries.removeLast().id);
    }
    tick.bump();
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
    final entry = byId(id);
    if (entry == null) return;
    entry.statusCode = statusCode;
    entry.responseHeaders = responseHeaders;
    entry.responseBody = _capBody(responseBody);
    entry.errorMessage = errorMessage;
    entry.completedAt = DateTime.now();
    entry.status = status;
    tick.bump();

    // Every adapter funnels through complete(), so hooking here forwards
    // failures from dio, http and any hand-rolled client alike.
    if (status == NetworkLogStatus.failed && _shouldReport(entry)) {
      DevtrayLog.instance.report(
        NetworkError(entry),
        // Transport failures have no useful Dart stack (the throw site is deep
        // in the HTTP client), so the entry itself is the diagnostic.
        source: ErrorSource.network,
        context: '${entry.method} ${entry.uri.path}',
      );
    }
  }

  bool _shouldReport(NetworkLogEntry entry) {
    final code = entry.statusCode;
    return switch (errorReporting.value) {
      NetworkErrorReporting.none => false,
      NetworkErrorReporting.all => true,
      // No status code at all = the request never completed: timeout, DNS
      // failure, refused connection, bad cert.
      NetworkErrorReporting.serverAndTransport => code == null || code >= 500,
    };
  }

  /// Attaches a named extra section to an entry; it becomes its own detail tab.
  void attachExtra(int id, String label, String content) {
    final entry = byId(id);
    if (entry == null) return;
    entry.extras[label] = content;
    tick.bump();
  }

  /// Truncates an oversized body so the buffer can't retain unbounded memory.
  ///
  /// Only `String` bodies are truncated. A structured body (dio hands over the
  /// already-decoded object) is left alone: measuring it means stringifying it,
  /// which is the very cost we're avoiding, and cutting an object graph in half
  /// would produce something that no longer round-trips.
  dynamic _capBody(dynamic body) {
    if (body is! String || body.length <= maxBodyChars) return body;
    return '${body.substring(0, maxBodyChars)}\n\n'
        '[devtray] truncated — ${body.length} characters total, kept $maxBodyChars. '
        'Raise DevtrayNet.instance.maxBodyChars to keep more.';
  }

  void clear() {
    _entries.clear();
    _byIdIndex.clear();
    tick.bump();
  }

  /// The entry with this id, or null once it's been evicted. O(1).
  NetworkLogEntry? byId(int id) => _byIdIndex[id];
}
