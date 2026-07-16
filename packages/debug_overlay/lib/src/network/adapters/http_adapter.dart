import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../curl_builder.dart';
import '../mocking/mock_interceptor.dart';
import '../mocking/mock_store.dart';
import '../network_log_store.dart';

/// A `package:http` client wrapper that captures every request into
/// [NetworkLogStore], and applies any mock rules from [MockStore] (delay / fake
/// response / simulated failure).
///
/// ```dart
/// final client = DebugHttpClient(http.Client());
/// final res = await client.get(Uri.parse('https://api.example.com/users'));
/// ```
///
/// Because it's a [http.BaseClient], it also drops into anything that accepts a
/// `Client` (Supabase, google APIs, generated OpenAPI clients, …).
///
/// Streamed responses are buffered so the body can be shown in the inspector —
/// the caller still gets a valid [http.StreamedResponse], but a very large
/// download will be held in memory. Add its URL to
/// `NetworkLogStore.instance.excludedUrlPatterns` to skip it entirely.
class DebugHttpClient extends http.BaseClient {
  final http.Client _inner;
  final NetworkLogStore _store;
  final MockStore _mocks;

  DebugHttpClient([http.Client? inner, NetworkLogStore? store, MockStore? mockStore])
      : _inner = inner ?? http.Client(),
        _store = store ?? NetworkLogStore.instance,
        _mocks = mockStore ?? MockStore.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final entry = _store.add(
      method: request.method,
      uri: request.url,
      requestHeaders: Map<String, dynamic>.from(request.headers),
      queryParameters: Map<String, dynamic>.from(request.url.queryParameters),
      requestBody: _snapshotBody(request),
    );

    // Note: mocking applies even when the URL is excluded from the log (entry
    // == null). Excluding a URL means "don't show it to me", not "don't mock it".
    final decision = decideMock(url: request.url.toString(), method: request.method, store: _mocks);

    switch (decision) {
      case PassThrough(:final delay):
        if (delay != null) await Future<void>.delayed(delay);

      case RespondWith(:final statusCode, :final body, :final headers, :final delay):
        if (delay != null) await Future<void>.delayed(delay);
        _markMocked(entry?.id, decision);

        final bytes = utf8.encode(body is String ? body : (body == null ? '' : jsonEncode(body)));
        if (entry != null) {
          _store.complete(
            entry.id,
            statusCode: statusCode,
            responseHeaders: {for (final e in headers.entries) e.key: [e.value]},
            responseBody: body,
            status: statusCode >= 400 ? NetworkLogStatus.failed : NetworkLogStatus.success,
          );
        }
        return http.StreamedResponse(
          Stream.value(bytes),
          statusCode,
          contentLength: bytes.length,
          request: request,
          headers: headers,
        );

      case FailWith(:final message, :final delay):
        if (delay != null) await Future<void>.delayed(delay);
        _markMocked(entry?.id, decision);

        if (entry != null) {
          _store.complete(entry.id, errorMessage: message, status: NetworkLogStatus.failed);
        }
        throw http.ClientException(message, request.url);
    }

    if (entry == null) return _inner.send(request);

    try {
      final streamed = await _inner.send(request);
      final bytes = await streamed.stream.toBytes();

      _store.complete(
        entry.id,
        statusCode: streamed.statusCode,
        responseHeaders: {for (final e in streamed.headers.entries) e.key: [e.value]},
        responseBody: _decode(bytes),
        status: streamed.statusCode >= 400 ? NetworkLogStatus.failed : NetworkLogStatus.success,
      );

      // Hand the caller a fresh response over the buffered bytes — the original
      // stream has already been drained.
      return http.StreamedResponse(
        Stream.value(bytes),
        streamed.statusCode,
        contentLength: bytes.length,
        request: streamed.request,
        headers: streamed.headers,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
        reasonPhrase: streamed.reasonPhrase,
      );
    } catch (e) {
      _store.complete(entry.id, errorMessage: e.toString(), status: NetworkLogStatus.failed);
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Badge the entry so a faked response can't be mistaken for a real one.
  void _markMocked(int? id, MockDecision decision) {
    if (id == null) return;
    _store.attachExtra(id, kMockedExtraLabel, switch (decision) {
      RespondWith(:final statusCode) => 'Response faked by debug_overlay (HTTP $statusCode). The server was never contacted.',
      FailWith(:final message) => 'Failure simulated by debug_overlay: $message. The server was never contacted.',
      PassThrough() => 'Delayed by debug_overlay.',
    });
  }

  dynamic _snapshotBody(http.BaseRequest request) {
    if (request is http.MultipartRequest) {
      return {
        kFormDataMarker: true,
        'fields': Map<String, String>.from(request.fields),
        'files': request.files.map((f) => {'key': f.field, 'filename': f.filename}).toList(),
      };
    }
    if (request is http.Request) return request.body.isEmpty ? null : request.body;
    // A raw StreamedRequest body can't be read without consuming it.
    return null;
  }

  String _decode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '<${bytes.length} bytes of binary data>';
    }
  }
}
