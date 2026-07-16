import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../device/device_info_provider.dart';
import '../widgets/copyable_section.dart';
import 'debug_report.dart';

/// Bundles everything captured — device, errors, network, logs — into one
/// plain-text bug report you can hand to someone.
///
/// Turns "it broke on my phone" into an actual report.
///
/// The report includes everything verbatim — headers, auth tokens, bodies.
///
/// ```dart
/// ExportDebugPage(
///   // Optional — include the same device facts DeviceDebugPage shows.
///   deviceInfoProvider: const PluginDeviceInfoProvider(),
///
///   // Optional — hand the report to the OS share sheet. Without this you get
///   // copy-to-clipboard, which needs no extra dependency.
///   onShare: (report) => Share.share(report),   // package:share_plus
/// )
/// ```
class ExportDebugPage extends DebugPage {
  /// Include a device section, from the same provider the Device page uses.
  final DeviceInfoProvider? deviceInfoProvider;

  /// Wire this to `share_plus` (or anything else) to get a Share button. The
  /// package takes no share dependency itself.
  final Future<void> Function(String report)? onShare;

  const ExportDebugPage({this.deviceInfoProvider, this.onShare});

  @override
  String get title => 'Export';

  @override
  IconData? get icon => Icons.ios_share;

  @override
  Widget build(BuildContext context) => _ExportView(
        deviceInfoProvider: deviceInfoProvider,
        onShare: onShare,
      );
}

class _ExportView extends StatefulWidget {
  final DeviceInfoProvider? deviceInfoProvider;
  final Future<void> Function(String report)? onShare;

  const _ExportView({this.deviceInfoProvider, this.onShare});

  @override
  State<_ExportView> createState() => _ExportViewState();
}

class _ExportViewState extends State<_ExportView> {
  bool _device = true;
  bool _errors = true;
  bool _network = true;
  bool _logs = true;

  Map<String, Map<String, String>>? _deviceInfo;
  bool _loadingDevice = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final provider = widget.deviceInfoProvider;
    if (provider == null) return;

    setState(() => _loadingDevice = true);
    try {
      final sections = await provider.load();
      if (!mounted) return;
      setState(() {
        _deviceInfo = {for (final s in sections) s.title: s.values};
        _loadingDevice = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevice = false);
    }
  }

  String _buildReport() => DebugReport.build(
        sections: DebugReportSections(device: _device, errors: _errors, network: _network, logs: _logs),
        deviceInfo: _deviceInfo,
      );

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final report = _buildReport();
    final anySelected = _device || _errors || _network || _logs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Include', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text)),
        Wrap(
          spacing: 8,
          children: [
            _Toggle(label: 'Device', value: _device, onChanged: (v) => setState(() => _device = v), theme: t),
            _Toggle(label: 'Errors', value: _errors, onChanged: (v) => setState(() => _errors = v), theme: t),
            _Toggle(label: 'Network', value: _network, onChanged: (v) => setState(() => _network = v), theme: t),
            _Toggle(label: 'Logs', value: _logs, onChanged: (v) => setState(() => _logs = v), theme: t),
          ],
        ),
        if (_loadingDevice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Loading device info…', style: TextStyle(fontSize: 11, color: t.textMuted)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${report.length} characters',
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ),
            if (widget.onShare != null) ...[
              FilledButton.icon(
                onPressed: anySelected ? () => widget.onShare!(report) : null,
                icon: const Icon(Icons.ios_share, size: 14),
                label: const Text('Share', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
            ],
            CopyButton(tooltip: 'Copy report', icon: Icons.copy_all, size: 18, text: anySelected ? report : ''),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6)),
            child: SingleChildScrollView(
              // Preview it. Nobody should share a blob they haven't seen.
              child: SelectableText(
                report,
                style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: t.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final DebugOverlayTheme theme;

  const _Toggle({required this.label, required this.value, required this.onChanged, required this.theme});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: value ? theme.accent : theme.textMuted)),
      selected: value,
      onSelected: onChanged,
      showCheckmark: false,
      backgroundColor: Colors.transparent,
      selectedColor: theme.accent.withValues(alpha: 0.15),
      side: BorderSide(color: value ? theme.accent : theme.border),
    );
  }
}
