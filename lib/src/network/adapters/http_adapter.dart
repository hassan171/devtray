import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../curl_builder.dart';
import '../network_log_store.dart';

/// A `package:http` client wrapper that captures every request into
/// [NetworkLogStore].
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

  DebugHttpClient([http.Client? inner, NetworkLogStore? store])
      : _inner = inner ?? http.Client(),
        _store = store ?? NetworkLogStore.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final entry = _store.add(
      method: request.method,
      uri: request.url,
      requestHeaders: Map<String, dynamic>.from(request.headers),
      queryParameters: Map<String, dynamic>.from(request.url.queryParameters),
      requestBody: _snapshotBody(request),
    );

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
