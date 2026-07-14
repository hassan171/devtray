/// A draggable in-app debugging overlay with a pluggable page system.
///
/// Ships with one page — the network inspector — and lets the host app add its
/// own. Wrap your app:
///
/// ```dart
/// DebugOverlay(
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
export 'src/core/debug_capture.dart';
export 'src/core/debug_launcher_button.dart';
export 'src/core/debug_overlay.dart';
export 'src/core/debug_overlay_controller.dart';
export 'src/core/debug_overlay_theme.dart';
export 'src/core/debug_page.dart';
export 'src/core/debug_tools_screen.dart';
export 'src/core/run_debug_app.dart';

// Network page
export 'src/network/adapters/dio_adapter.dart';
export 'src/network/adapters/http_adapter.dart';
export 'src/network/components/network_search_bar.dart' show NetworkErrorReportingButton;
export 'src/network/curl_builder.dart';
export 'src/network/network_debug_page.dart';
export 'src/network/network_log_store.dart';

// Logs page
export 'src/logs/log_bridge.dart';
export 'src/logs/log_store.dart';
export 'src/logs/logs_debug_page.dart';

// Errors page
export 'src/errors/error_store.dart';
export 'src/errors/errors_debug_page.dart';

// Device page
export 'src/device/device_debug_page.dart';
export 'src/device/device_info_provider.dart';
export 'src/device/plugin_device_info_provider.dart';

// Reusable widgets — for building your own pages in the same visual language.
export 'src/widgets/copyable_section.dart';
export 'src/widgets/debug_search_bar.dart';
export 'src/widgets/debug_tab_bar.dart';
export 'src/widgets/html_preview_dialog.dart';
