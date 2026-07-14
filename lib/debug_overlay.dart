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
export 'src/core/debug_launcher_button.dart';
export 'src/core/debug_overlay.dart';
export 'src/core/debug_overlay_controller.dart';
export 'src/core/debug_overlay_theme.dart';
export 'src/core/debug_page.dart';
export 'src/core/debug_tools_screen.dart';

// Network page
export 'src/network/adapters/dio_adapter.dart';
export 'src/network/adapters/http_adapter.dart';
export 'src/network/curl_builder.dart';
export 'src/network/network_debug_page.dart';
export 'src/network/network_log_store.dart';

// Reusable widgets — for building your own pages in the same visual language.
export 'src/widgets/copyable_section.dart';
export 'src/widgets/debug_tab_bar.dart';
export 'src/widgets/html_preview_dialog.dart';
