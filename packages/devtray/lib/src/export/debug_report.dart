import 'dart:convert';

import '../logs/devtray_log.dart';
import '../network/devtray_net.dart';

/// Which sections to include in a report.
class DebugReportSections {
  final bool device;
  final bool errors;
  final bool network;
  final bool logs;

  const DebugReportSections({
    this.device = true,
    this.errors = true,
    this.network = true,
    this.logs = true,
  });

  bool get any => device || errors || network || logs;
}

/// Builds a single plain-text bug report from everything the overlay has
/// captured — device info, errors, network traffic, logs.
///
/// Bodies and most headers are included **verbatim** — that's what makes the
/// report worth reading, since a scrubbed one can't be replayed or diagnosed
/// from. The one exception is headers named in [Devtray.network]'s
/// `hideHeaders`: their values are masked here as everywhere else, so a token
/// doesn't ride along into a ticket a user pastes the report into.
///
/// ```dart
/// final report = DebugReport.build();
/// // hand it to share_plus, write it to a file, POST it somewhere…
/// ```
class DebugReport {
  const DebugReport._();

  /// Most recent first within each section, matching what the pages show.
  ///
  /// [deviceInfo] is passed in rather than read from a store, because it comes
  /// from a `DeviceInfoProvider` the host app configures. Omit it and the
  /// section is skipped.
  static String build({
    DebugReportSections sections = const DebugReportSections(),
    Map<String, Map<String, String>>? deviceInfo,
    int maxNetworkEntries = 50,
    int maxLogEntries = 200,
    int maxErrors = 20,
  }) {
    final buffer = StringBuffer()
      ..writeln('# Debug report')
      ..writeln();

    if (sections.device && deviceInfo != null && deviceInfo.isNotEmpty) {
      buffer.writeln('## Device');
      for (final section in deviceInfo.entries) {
        buffer.writeln('### ${section.key}');
        for (final e in section.value.entries) {
          buffer.writeln('${e.key}: ${e.value}');
        }
        buffer.writeln();
      }
    }

    if (sections.errors) {
      // Errors are the error-level entries of the one log store.
      final allErrors = DevtrayLog.instance.entries.where((e) => e.isError).toList();
      final errors = allErrors.take(maxErrors).toList();
      buffer.writeln('## Errors (${allErrors.length})');
      if (errors.isEmpty) buffer.writeln('None.');

      for (final e in errors) {
        buffer
          ..writeln('### ${e.title}')
          ..writeln('Source: ${e.source!.name}')
          ..writeln('Time: ${e.time.toIso8601String()}');
        if (e.errorContext != null) buffer.writeln('Context: ${e.errorContext}');
        if (e.stackTrace != null) {
          buffer
            ..writeln('```')
            ..writeln(e.stackTrace.toString())
            ..writeln('```');
        }
        buffer.writeln();
      }
      buffer.writeln();
    }

    if (sections.network) {
      final entries = DevtrayNet.instance.entries.take(maxNetworkEntries).toList();
      buffer.writeln('## Network (${DevtrayNet.instance.entries.length})');
      if (entries.isEmpty) buffer.writeln('None.');

      for (final e in entries) {
        final code = e.statusCode?.toString() ?? e.status.name;
        buffer
          ..writeln('### ${e.method} ${e.uri} → $code')
          ..writeln('Duration: ${e.duration?.inMilliseconds ?? '-'}ms')
          // Redacted, like the pane and cURL — a bug report a user pastes into
          // a ticket is the last place a token should survive.
          ..writeln('Request headers: ${_json(DevtrayNet.instance.redactHeaders(e.requestHeaders))}');
        if (e.requestBody != null) buffer.writeln('Request body: ${_json(e.requestBody)}');
        buffer.writeln('Response headers: ${_json(DevtrayNet.instance.redactResponseHeaders(e.responseHeaders))}');
        if (e.responseBody != null) buffer.writeln('Response body: ${_json(e.responseBody)}');
        if (e.errorMessage != null) buffer.writeln('Error: ${e.errorMessage}');
        buffer.writeln();
      }
      buffer.writeln();
    }

    if (sections.logs) {
      final logs = DevtrayLog.instance.entries.take(maxLogEntries).toList();
      buffer
        ..writeln('## Logs (${DevtrayLog.instance.entries.length})')
        ..writeln('```');
      // Oldest first, so a pasted dump reads chronologically.
      for (final e in logs.reversed) {
        final tag = e.tag == null ? '' : '[${e.tag}] ';
        buffer.writeln('${e.time.toIso8601String()} ${e.level.name.toUpperCase()} $tag${e.message}');
      }
      buffer.writeln('```');
    }

    return buffer.toString();
  }

  static String _json(Object? value) {
    if (value == null) return 'null';
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
