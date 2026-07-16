import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
import '../widgets/debug_copy_button.dart';
import 'device_info_provider.dart';

/// Device, OS, app and screen facts — the first thing anyone asks for in a bug
/// report, and the whole page can be copied out as one block of text.
///
/// Screen metrics are read live from the [MediaQuery], so they stay correct
/// across rotation and window resizes. Everything else comes from [provider].
class DeviceDebugPage extends DebugPage {
  /// Defaults to build mode + platform only, which needs no plugins. Pass
  /// [PluginDeviceInfoProvider] (or your own) for device model, OS and app
  /// version, and use [CompositeDeviceInfoProvider] to add your own sections.
  final DeviceInfoProvider provider;

  const DeviceDebugPage({this.provider = const RuntimeDeviceInfoProvider()});

  @override
  String get title => 'Device';

  @override
  IconData? get icon => Icons.phone_iphone;

  @override
  Widget build(BuildContext context) => _DeviceView(provider: provider);
}

class _DeviceView extends StatefulWidget {
  final DeviceInfoProvider provider;
  const _DeviceView({required this.provider});

  @override
  State<_DeviceView> createState() => _DeviceViewState();
}

class _DeviceViewState extends State<_DeviceView> {
  late final Future<List<DeviceInfoSection>> _future = widget.provider.load();

  /// Live values — these change under you, so they're read at build time rather
  /// than captured once in the future above.
  DeviceInfoSection _screenSection(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return DeviceInfoSection('Screen', {
      'Size': '${size.width.toStringAsFixed(1)} × ${size.height.toStringAsFixed(1)} dp',
      'Pixels': '${(size.width * mq.devicePixelRatio).round()} × ${(size.height * mq.devicePixelRatio).round()} px',
      'Device pixel ratio': mq.devicePixelRatio.toStringAsFixed(2),
      'Orientation': mq.orientation.name,
      'Text scale': mq.textScaler.scale(14).toStringAsFixed(2),
      'Platform brightness': mq.platformBrightness.name,
      'Locale': Localizations.maybeLocaleOf(context)?.toString() ?? 'unknown',
      'Safe area': 'top ${mq.padding.top.round()}, bottom ${mq.padding.bottom.round()}',
    });
  }

  String _asPlainText(List<DeviceInfoSection> sections) => sections
      .map((s) => '## ${s.title}\n${s.values.entries.map((e) => '${e.key}: ${e.value}').join('\n')}')
      .join('\n\n');

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return FutureBuilder<List<DeviceInfoSection>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: t.accent));
        }
        if (snapshot.hasError) {
          return _LoadFailed(error: snapshot.error!);
        }

        final sections = [...?snapshot.data, _screenSection(context)];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Device info',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text),
                  ),
                ),
                // The whole page as one block — this page exists to be pasted
                // into a bug report.
                DebugCopyButton(text: () => _asPlainText(sections)),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  for (final section in sections) _InfoTable(section: section),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The provider threw. Say which one and why — a bare red string leaves you
/// guessing whether the page or your own provider is broken.
class _LoadFailed extends StatelessWidget {
  final Object error;
  const _LoadFailed({required this.error});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 28, color: t.error),
            const SizedBox(height: 8),
            Text(
              'Could not load device info',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              'The DeviceInfoProvider threw:',
              style: TextStyle(fontSize: 11, color: t.textMuted),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.error.withValues(alpha: 0.4)),
              ),
              child: SelectableText(
                '$error',
                style: DebugTextStyles.debugMono(color: t.error, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One section as a `key: value` table.
class _InfoTable extends StatelessWidget {
  final DeviceInfoSection section;
  const _InfoTable({required this.section});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Section title as a ruled header — the same one the State page uses, so
        // sections read alike across the overlay.
        Row(
          children: [
            Text(section.title, style: DebugTextStyles.label(color: t.textMuted, fontSize: 10)),
            const SizedBox(width: 6),
            Expanded(child: Container(height: 1, color: t.border.withValues(alpha: 0.6))),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.border.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            children: [
              for (final e in section.values.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A max, not a fixed width. At 140 fixed, 'Locale' wasted
                      // a third of a 375px row before its value even started —
                      // and a longer key from a custom provider had nowhere to
                      // go. Now short keys give their space back to the value.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          e.key,
                          style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          e.value,
                          // Mono: these are machine values — versions, ratios,
                          // pixel counts — and they're read as data, often
                          // compared between two devices.
                          style: DebugTextStyles.debugMono(color: t.text, fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
