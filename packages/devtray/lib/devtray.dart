/// A draggable in-app debugging overlay with a pluggable page system.
///
/// Ships with one page — the network inspector — and lets the host app add its
/// own. Wrap your app:
///
/// ```dart
/// Devtray(
///   enabled: kDebugMode,
///   pages: const [NetworkDebugPage()],
///   child: MaterialApp(...),
/// )
/// ```
///
/// Then feed the network page from your HTTP client:
///
/// ```dart
/// dio.interceptors.add(DebugDioInterceptor());          // dio
/// final client = DebugHttpClient(http.Client());        // package:http
/// NetworkLogStore.instance.add(...);                    // anything else
/// ```
library;

// Core
export 'src/core/debug_launcher_button.dart';
export 'src/core/devtray.dart';
export 'src/core/devtray_controller.dart';
export 'src/core/devtray_kill_switch.dart';
export 'src/core/devtray_theme.dart';
export 'src/core/debug_page.dart';
// Typography — so a custom page's data reads like the built-in pages' data.
export 'src/core/debug_text_styles.dart';
export 'src/core/debug_tools_screen.dart';
export 'src/core/run_debug_app.dart';

// Network page
export 'src/network/curl_builder.dart';
// The shape of an HTML previewer. The renderer itself lives in
// devtray_html — see DebugHtmlPreviewer for why it isn't in here.
export 'src/network/html_previewer.dart';
export 'src/network/mocking/components/mock_rule_editor.dart';
export 'src/network/mocking/mock_interceptor.dart';
export 'src/network/mocking/mock_rule.dart';
export 'src/network/mocking/mock_store.dart';
export 'src/network/mocking/mocks_view.dart';
export 'src/network/network_debug_page.dart';
export 'src/network/network_log_store.dart';
// The row, mostly for its `extent` — a custom page rendering the same list
// needs the same fixed height to set `itemExtent`.
export 'src/network/components/network_log_row.dart';

// Logs page
export 'src/logs/log_bridge.dart';
export 'src/logs/components/log_detail_dialog.dart';
export 'src/logs/log_store.dart';
export 'src/logs/logs_debug_page.dart';

// Log persistence — the shape of a sink, the batching, and the file format.
// The transports themselves live outside the core (see devtray_log_file), which
// carries no dependencies and cannot reach dart:io or the filesystem.
export 'src/logs/log_sink.dart';
export 'src/logs/components/log_session_picker.dart';

// Errors — no separate store or page. Errors live in the one LogStore as
// error-level entries (LogStore.report / captureErrors, ErrorSource, the badge)
// and render in the Logs page. This is just the shared detail renderer.
export 'src/logs/error_log_detail.dart' show ErrorDetailSections, LogFieldsSection, errorSourceLabel, errorAsPlainText, requestSummary;

// Advanced filtering — the JQL-style condition builder, reusable on any page.
export 'src/filter/debug_filter.dart';
export 'src/filter/debug_filter_builder.dart';

// Device page
export 'src/device/device_debug_page.dart';
export 'src/device/device_info_provider.dart';

// Visual debug flags page
export 'src/visual/visual_debug_page.dart';

// Export — bundle everything captured into one shareable bug report.
export 'src/export/debug_report.dart';
export 'src/export/export_debug_page.dart';

// State page — live state + change history for any state library.
export 'src/state/debug_inspectable.dart';
export 'src/state/state_bridge.dart';
export 'src/state/state_debug_page.dart';
export 'src/state/state_inspector.dart';

// Storage page — browse and edit key/value storage at runtime.
export 'src/storage/components/storage_list_editor.dart';
export 'src/storage/components/storage_value_editor.dart';
export 'src/storage/debug_storage_adapter.dart';
export 'src/storage/storage_debug_page.dart';

// Reusable widgets — for building your own pages in the same visual language.
export 'src/widgets/copyable_section.dart';
export 'src/widgets/debug_copy_button.dart';
export 'src/widgets/debug_search_bar.dart';
export 'src/widgets/jump_to_latest_button.dart';
export 'src/widgets/debug_tab_bar.dart';
