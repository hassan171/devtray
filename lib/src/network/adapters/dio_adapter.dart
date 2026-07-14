import 'package:dio/dio.dart';

import '../curl_builder.dart';
import '../network_log_store.dart';

const String _logIdKey = '__debug_overlay_netlog_id';

/// Captures every dio request into [NetworkLogStore].
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

  DebugDioInterceptor({NetworkLogStore? store}) : _store = store ?? NetworkLogStore.instance;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final entry = _store.add(
      method: options.method,
      uri: options.uri,
      requestHeaders: Map<String, dynamic>.from(options.headers),
      queryParameters: Map<String, dynamic>.from(options.queryParameters),
      requestBody: _snapshotBody(options.data),
    );
    if (entry != null) options.extra[_logIdKey] = entry.id;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra[_logIdKey];
    if (id is int) {
      _store.complete(
        id,
        statusCode: response.statusCode,
        responseHeaders: Map<String, List<String>>.from(response.headers.map),
        responseBody: response.data,
        status: NetworkLogStatus.success,
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
