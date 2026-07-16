import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
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
    final t = DevtrayTheme.of(context);
    final report = _buildReport();
    final anySelected = _device || _errors || _network || _logs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // This page's one dangerous property, stated where the decision is
        // made. The report carries auth tokens and request bodies verbatim
        // (deliberately — it has to be complete enough to replay from), and the
        // moment you're about to hand it to someone is the moment to know that.
        // It was previously only in the dartdoc, i.e. visible to whoever added
        // the page and to nobody who uses it.
        const _VerbatimWarning(),
        const SizedBox(height: 10),

        Row(
          children: [
            Text('Include', style: DebugTextStyles.label(color: t.textMuted, fontSize: 10)),
            const SizedBox(width: 6),
            Expanded(child: Container(height: 1, color: t.border.withValues(alpha: 0.6))),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Toggle(label: 'Device', value: _device, onChanged: (v) => setState(() => _device = v)),
            _Toggle(label: 'Errors', value: _errors, onChanged: (v) => setState(() => _errors = v)),
            _Toggle(label: 'Network', value: _network, onChanged: (v) => setState(() => _network = v)),
            _Toggle(label: 'Logs', value: _logs, onChanged: (v) => setState(() => _logs = v)),
          ],
        ),
        if (_loadingDevice)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: t.textMuted)),
                const SizedBox(width: 6),
                Text('Loading device info…', style: TextStyle(fontSize: 11, color: t.textMuted)),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                // Deselecting everything doesn't produce an empty report — the
                // builder still emits a header — so a raw character count would
                // claim there's something to send when there isn't.
                anySelected ? '${report.length} characters' : 'Nothing selected',
                style: DebugTextStyles.debugMono(
                  color: anySelected ? t.textMuted : t.warning,
                  fontSize: 11,
                ),
              ),
            ),
            if (widget.onShare != null) ...[
              FilledButton.icon(
                onPressed: anySelected ? () => widget.onShare!(report) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
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
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.border.withValues(alpha: 0.6)),
            ),
            child: SingleChildScrollView(
              // Preview it. Nobody should share a blob they haven't seen.
              child: SelectableText(
                report,
                style: DebugTextStyles.debugMono(color: t.text, fontSize: 10, height: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The report is not redacted, and that's on purpose — it has to be complete
/// enough to diagnose from and replay. Which makes it exactly the kind of thing
/// people paste into a public issue tracker without thinking.
class _VerbatimWarning extends StatelessWidget {
  const _VerbatimWarning();

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        border: Border.all(color: t.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.key_off_outlined, size: 14, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nothing is redacted. Auth tokens, headers and request bodies are '
              'included verbatim, so the report can be replayed. Check the '
              'preview before sending it anywhere public.',
              style: TextStyle(fontSize: 11, color: t.text, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// One section of the report, on or off.
///
/// Hand-built rather than a `FilterChip`: the stock chip animates its own
/// selection and, at this size, spends most of its height on Material padding
/// we then fight. This matches the filter chips on the Logs and Network pages,
/// which is what these actually are.
class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          // 32px tall — a chip you tap, not a label. Sits inside an 8px-spaced
          // Wrap, so neighbouring targets stay apart.
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: value ? t.accent.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(color: value ? t.accent : t.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Not colour alone: a check says "included" in grayscale, and the
              // box keeps the chip's width stable across the toggle so the Wrap
              // doesn't reflow under your finger.
              Icon(
                value ? Icons.check_rounded : Icons.remove_rounded,
                size: 12,
                color: value ? t.accent : t.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  color: value ? t.accent : t.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
