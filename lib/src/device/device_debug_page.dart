import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../widgets/copyable_section.dart';
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
          return Center(
            child: Text('Could not load device info:\n${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: t.error)),
          );
        }

        final sections = [...?snapshot.data, _screenSection(context)];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Device info', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.text)),
                ),
                TextButton.icon(
                  icon: Icon(Icons.copy, size: 14, color: t.accent),
                  label: Text('Copy all', style: TextStyle(fontSize: 12, color: t.accent)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _asPlainText(sections)));
                    showDebugToast('Device info copied');
                  },
                ),
              ],
            ),
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
        Text(section.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.accent)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              for (final e in section.values.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(e.key, style: TextStyle(fontSize: 11, color: t.textMuted)),
                      ),
                      Expanded(
                        child: SelectableText(
                          e.value,
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
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
