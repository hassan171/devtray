import 'dart:convert';

/// Marker key used by the adapters to snapshot a multipart body into a plain
/// map (the real FormData/MultipartRequest object can't be retained safely).
const String kFormDataMarker = '__formData';

/// Renders a copy-pasteable `curl` command from a captured entry's parts.
String buildCurl({
  required String method,
  required Uri uri,
  required Map<String, dynamic> headers,
  required dynamic data,
}) {
  // Multipart bodies arrive as {'__formData': true, 'fields': {...}, 'files': [...]}
  // — emit -F flags instead of dumping the snapshot map as a JSON -d body.
  final isFormData = data is Map && data[kFormDataMarker] == true;

  final parts = <String>['curl -X ${method.toUpperCase()}'];
  headers.forEach((k, v) {
    if (v == null) return;
    // A multipart request must let curl pick the boundary itself.
    if (isFormData && k.toLowerCase() == 'content-type') return;
    parts.add("-H '$k: $v'");
  });

  if (isFormData) {
    final fields = data['fields'];
    if (fields is Map) fields.forEach((k, v) => parts.add("-F '$k=$v'"));
    final files = data['files'];
    if (files is List) {
      for (final f in files) {
        if (f is Map) parts.add("-F '${f['key']}=@${f['filename']}'");
      }
    }
  } else if (data != null) {
    final jsonStr = data is Map || data is List ? jsonEncode(data) : data.toString();
    if (jsonStr.isNotEmpty && jsonStr != '{}') {
      parts.add("-d '${jsonStr.replaceAll("'", r"\'")}'");
    }
  }

  parts.add("'$uri'");
  return parts.join(' \\\n  ');
}
