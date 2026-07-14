import 'dart:convert';

String formatDuration(Duration? d) {
  if (d == null) return '...';
  final ms = d.inMilliseconds;
  return ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(2)}s';
}

String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

String prettyJson(dynamic data) {
  if (data == null) return '';
  if (data is String) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(data));
    } catch (_) {
      return data;
    }
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

String prettyMap(Map<String, dynamic> map) => map.isEmpty ? '' : map.entries.map((e) => '${e.key}: ${e.value}').join('\n');

String prettyHeaders(Map<String, List<String>> headers) =>
    headers.isEmpty ? '' : headers.entries.map((e) => '${e.key}: ${e.value.join(', ')}').join('\n');
