import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../network_log_store.dart';

/// Search field + result count + error-reporting toggle + clear-all button.
class NetworkSearchBar extends StatelessWidget {
  final int total;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const NetworkSearchBar({super.key, required this.total, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Row(
      children: [
        Expanded(
          child: TextField(
            style: TextStyle(color: t.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search URL, method, status',
              hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: t.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.accent)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Text('$total', style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(width: 8),
        const NetworkErrorReportingButton(),
        IconButton(
          tooltip: 'Clear',
          onPressed: onClear,
          icon: Icon(Icons.delete_outline, color: t.error),
        ),
      ],
    );
  }
}

/// Toggles which failed requests get forwarded to the Errors page. Live — flips
/// [NetworkLogStore.errorReporting], which the store reads on every completion.
class NetworkErrorReportingButton extends StatelessWidget {
  const NetworkErrorReportingButton({super.key});

  static String labelOf(NetworkErrorReporting mode) => switch (mode) {
        NetworkErrorReporting.none => "Don't report failures",
        NetworkErrorReporting.serverAndTransport => 'Report 5xx + transport failures',
        NetworkErrorReporting.all => 'Report all failures (incl. 4xx)',
      };

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final notifier = NetworkLogStore.instance.errorReporting;

    return ValueListenableBuilder<NetworkErrorReporting>(
      valueListenable: notifier,
      builder: (context, mode, _) {
        final isOff = mode == NetworkErrorReporting.none;

        return PopupMenuButton<NetworkErrorReporting>(
          tooltip: 'Report failures to the Errors page',
          initialValue: mode,
          onSelected: (value) => notifier.value = value,
          color: t.background,
          icon: Icon(
            isOff ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
            size: 20,
            color: isOff ? t.textMuted : t.accent,
          ),
          itemBuilder: (context) => [
            for (final option in NetworkErrorReporting.values)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      option == mode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 16,
                      color: option == mode ? t.accent : t.textMuted,
                    ),
                    const SizedBox(width: 8),
                    // The labels are long — without this they overflow the menu
                    // on a narrow screen.
                    Flexible(
                      child: Text(labelOf(option), style: TextStyle(fontSize: 12, color: t.text)),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
