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

/// Memo for [prettyJson], keyed by body identity.
///
/// Pretty-printing decodes *and* re-encodes the payload — two full passes — and
/// the detail pane calls it from `build()`, which re-runs whenever any other
/// request completes. Bodies are immutable once captured, so the result for a
/// given object never changes.
///
/// An [Expando] rather than a Map: it hangs the result off the body object
/// itself, so a cached string dies with the entry that owns it instead of
/// pinning evicted bodies in a cache nobody prunes.
final Expando<String> _prettyJsonCache = Expando<String>('prettyJson');

/// How large a payload may be before it's shown raw instead of formatted.
///
/// Beyond this, decode+re-encode costs more than the indentation is worth and
/// stalls the UI isolate on the tap that opens the pane.
const int _prettyJsonLimit = 512 * 1024;

String prettyJson(dynamic data) {
  if (data == null) return '';

  // Expando keys must be objects with identity — numbers, bools and strings
  // can't be used. Strings are the common case, so they get the size guard but
  // are re-formatted each call; they're cheap relative to an object graph.
  final cacheable = data is! String && data is! num && data is! bool;
  if (cacheable) {
    final hit = _prettyJsonCache[data as Object];
    if (hit != null) return hit;
  }

  String result;
  if (data is String) {
    if (data.length > _prettyJsonLimit) return data;
    try {
      result = const JsonEncoder.withIndent('  ').convert(jsonDecode(data));
    } catch (_) {
      return data;
    }
  } else {
    try {
      result = const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      result = data.toString();
    }
  }

  if (cacheable) _prettyJsonCache[data as Object] = result;
  return result;
}

String prettyMap(Map<String, dynamic> map) => map.isEmpty ? '' : map.entries.map((e) => '${e.key}: ${e.value}').join('\n');

String prettyHeaders(Map<String, List<String>> headers) => headers.isEmpty ? '' : headers.entries.map((e) => '${e.key}: ${e.value.join(', ')}').join('\n');
