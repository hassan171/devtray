import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../mocking/mock_interceptor.dart';
import '../network_log_store.dart';
import 'network_badges.dart';
import 'network_formatters.dart';

/// Marks a row whose response never came from the server.
class _MockedBadge extends StatelessWidget {
  const _MockedBadge();

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.2),
        border: Border.all(color: t.warning),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'MOCKED',
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: t.warning),
      ),
    );
  }
}

/// One row in the request list: method, path/host, status, duration.
class NetworkLogRow extends StatelessWidget {
  final NetworkLogEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const NetworkLogRow({super.key, required this.entry, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final failed = entry.status == NetworkLogStatus.failed;
    final pending = entry.status == NetworkLogStatus.pending;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? t.accent.withValues(alpha: 0.12)
              : failed
                  ? t.error.withValues(alpha: 0.06)
                  : null,
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Row(
          children: [
            MethodBadge(method: entry.method),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.uri.path.isEmpty ? entry.uri.toString() : entry.uri.path,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.text),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      // Never let a faked response pass for a real one.
                      if (entry.extras.containsKey(kMockedExtraLabel)) ...[
                        const _MockedBadge(),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          entry.uri.host,
                          style: TextStyle(fontSize: 10, color: t.textMuted),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (pending)
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted))
            else
              StatusBadge(code: entry.statusCode, failed: failed),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: Text(
                formatDuration(entry.duration),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
