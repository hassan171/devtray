import 'package:devtray/devtray.dart';
import 'package:dio/dio.dart';

const String _logIdKey = '__devtray_netlog_id';

/// Captures every dio request into [NetworkLogStore], and applies any mock rules
/// from [MockStore] (delay / fake response / simulated failure).
///
/// ```dart
/// dio.interceptors.add(DebugDioInterceptor());
/// ```
///
/// Add it **last** so it sees the final headers other interceptors set (auth
/// tokens, etc.). To keep noisy endpoints out of the list, populate
/// `NetworkLogStore.instance.excludedUrlPatterns`.
class DebugDioInterceptor extends Interceptor {
  final NetworkLogStore _store;
  final MockStore _mocks;

  DebugDioInterceptor({NetworkLogStore? store, MockStore? mockStore})
      : _store = store ?? NetworkLogStore.instance,
        _mocks = mockStore ?? MockStore.instance;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final entry = _store.add(
      method: options.method,
      uri: options.uri,
      requestHeaders: Map<String, dynamic>.from(options.headers),
      queryParameters: Map<String, dynamic>.from(options.queryParameters),
      requestBody: _snapshotBody(options.data),
    );
    if (entry != null) options.extra[_logIdKey] = entry.id;

    final decision = decideMock(url: options.uri.toString(), method: options.method, store: _mocks);

    switch (decision) {
      case PassThrough(:final delay):
        if (delay != null) await Future<void>.delayed(delay);
        handler.next(options);

      case RespondWith(:final statusCode, :final body, :final headers, :final delay):
        if (delay != null) await Future<void>.delayed(delay);
        _markMocked(entry?.id, decision);

        // resolve()/reject() short-circuit the chain and skip THIS interceptor's
        // own onResponse/onError, so the entry must be completed by hand here —
        // otherwise a mocked request sits "pending" in the log forever.
        if (entry != null) {
          _store.complete(
            entry.id,
            statusCode: statusCode,
            responseHeaders: {for (final e in headers.entries) e.key: [e.value]},
            responseBody: body,
            status: statusCode >= 400 ? NetworkLogStatus.failed : NetworkLogStatus.success,
          );
        }

        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
            data: body,
            headers: Headers.fromMap({for (final e in headers.entries) e.key: [e.value]}),
          ),
        );

      case FailWith(:final message, :final delay):
        if (delay != null) await Future<void>.delayed(delay);
        _markMocked(entry?.id, decision);

        if (entry != null) {
          _store.complete(entry.id, errorMessage: message, status: NetworkLogStatus.failed);
        }

        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: message,
            error: message,
          ),
        );
    }
  }

  /// Badge the entry so a faked response can't be mistaken for a real one.
  void _markMocked(int? id, MockDecision decision) {
    if (id == null) return;
    _store.attachExtra(id, kMockedExtraLabel, switch (decision) {
      RespondWith(:final statusCode) => 'Response faked by devtray (HTTP $statusCode). The server was never contacted.',
      FailWith(:final message) => 'Failure simulated by devtray: $message. The server was never contacted.',
      PassThrough() => 'Delayed by devtray.',
    });
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra[_logIdKey];
    if (id is int) {
      final code = response.statusCode;
      _store.complete(
        id,
        statusCode: code,
        responseHeaders: Map<String, List<String>>.from(response.headers.map),
        responseBody: response.data,
        // Derive from the code rather than assuming success: dio only throws on
        // 4xx/5xx when validateStatus says so, and plenty of apps set
        // `validateStatus: (_) => true`. Those error responses arrive here, and
        // hardcoding success would log a 500 as a green row.
        status: code != null && code >= 400 ? NetworkLogStatus.failed : NetworkLogStatus.success,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra[_logIdKey];
    if (id is int) {
      _store.complete(
        id,
        statusCode: err.response?.statusCode,
        responseHeaders: err.response == null ? const {} : Map<String, List<String>>.from(err.response!.headers.map),
        responseBody: err.response?.data,
        errorMessage: err.message ?? err.toString(),
        status: NetworkLogStatus.failed,
      );
    }
    handler.next(err);
  }

  dynamic _snapshotBody(dynamic data) {
    // FormData streams are single-use — snapshot the parts rather than holding
    // a reference we could accidentally consume when rendering.
    if (data is FormData) {
      return {
        kFormDataMarker: true,
        'fields': {for (final f in data.fields) f.key: f.value},
        'files': data.files.map((e) => {'key': e.key, 'filename': e.value.filename}).toList(),
      };
    }
    return data;
  }
}
