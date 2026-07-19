import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../network/components/network_formatters.dart';
import '../network/devtray_net.dart';
import '../widgets/copyable_section.dart';
import 'devtray_log.dart';

String errorSourceLabel(ErrorSource s) => switch (s) {
      ErrorSource.flutter => 'Flutter',
      ErrorSource.uncaught => 'Uncaught',
      ErrorSource.network => 'Network',
      ErrorSource.reported => 'Reported',
    };

/// The request side of a failed call, as a copyable block.
String requestSummary(NetworkError e) {
  final entry = e.entry;
  return [
    '${entry.method} ${entry.uri}',
    'Status: ${entry.statusCode ?? 'no response'}',
    'Duration: ${formatDuration(entry.duration)}',
    if (entry.errorMessage != null) 'Error: ${entry.errorMessage}',
    '',
    'Request Headers:',
    prettyMap(entry.requestHeaders),
    if (entry.requestBody != null) ...['', 'Request Body:', prettyJson(entry.requestBody)],
  ].join('\n');
}

/// The full error report as plain text — used by the copy button on an expanded
/// error row.
String errorAsPlainText(LogEntry e) {
  if (e.error case final NetworkError n) {
    return [
      n.toString(),
      '',
      requestSummary(n),
      '',
      'Response Headers:',
      prettyHeaders(n.entry.responseHeaders),
      '',
      'Response Body:',
      prettyJson(n.entry.responseBody),
    ].join('\n');
  }

  return [
    e.error?.toString() ?? e.message,
    if (e.errorContext != null) '\nContext: ${e.errorContext}',
    if (e.library != null) 'Library: ${e.library}',
    // Above the stack: on a pasted bug report, who and where beats the frames.
    if (e.fields.isNotEmpty) '\nFields:\n${e.fields.entries.map((f) => '  ${f.key}: ${f.value}').join('\n')}',
    if (e.stackTrace != null) '\n${e.stackTrace}',
  ].join('\n');
}

/// [LogEntry.fields] as a copyable block.
///
/// One widget rather than the same three lines in both callers: the error
/// report and the plain-log dialog both show fields, and having written it
/// twice I promptly rendered it twice on the same entry. Shared, that can't
/// happen — and the two can't drift apart either.
class LogFieldsSection extends StatelessWidget {
  final Map<String, Object?> fields;

  const LogFieldsSection({super.key, required this.fields});

  @override
  Widget build(BuildContext context) => CopyableSection(
        title: 'Fields',
        body: fields.entries.map((f) => '${f.key}: ${f.value}').join('\n'),
      );
}

/// The copyable sections that make up an error report: exception, context,
/// library, and either the request/response (network errors) or the stack
/// trace. Rendered from a [LogEntry] — the single store's error-level entry.
class ErrorDetailSections extends StatelessWidget {
  final LogEntry entry;
  const ErrorDetailSections({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CopyableSection(title: 'Exception', body: entry.error?.toString() ?? entry.message, titleColor: t.error),
        if (entry.errorContext != null) CopyableSection(title: 'Context', body: entry.errorContext!),
        if (entry.library != null) CopyableSection(title: 'Library', body: entry.library!),

        // Ambient context and enrichers — on an unanticipated error these are
        // often the most useful thing on screen, since nobody chose to capture
        // them at the throw site.
        if (entry.fields.isNotEmpty) LogFieldsSection(fields: entry.fields),

        // A failed request has no useful Dart stack — the throw site is deep
        // inside the HTTP client. Show the request instead; that's the actual
        // diagnostic.
        if (entry.error case final NetworkError e) ...[
          CopyableSection(title: 'Request', body: requestSummary(e)),
          CopyableSection(title: 'Response Headers', body: prettyHeaders(e.entry.responseHeaders)),
          CopyableSection(title: 'Response Body', body: prettyJson(e.entry.responseBody)),
        ] else
          CopyableSection(title: 'Stack Trace', body: entry.stackTrace?.toString() ?? 'No stack trace'),

        const SizedBox(height: 8),
      ],
    );
  }
}
