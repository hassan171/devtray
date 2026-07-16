import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../network/components/network_formatters.dart';
import '../network/network_log_store.dart';
import '../widgets/copyable_section.dart';
import 'log_store.dart';

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
    if (e.stackTrace != null) '\n${e.stackTrace}',
  ].join('\n');
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
