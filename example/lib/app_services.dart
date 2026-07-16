import 'package:devtray/devtray.dart';
import 'package:devtray_dio/devtray_dio.dart';
import 'package:devtray_http/devtray_http.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'counter_cubit.dart';

/// The app's long-lived objects.
///
/// In their own file rather than in `main.dart` so the screens can reach them
/// without importing the file that imports *them* — a cycle Dart allows but
/// nobody enjoys reading.
///
/// A real app would inject these (Riverpod providers, get_it, an InheritedWidget).
/// Globals here keep the example's wiring visible in one place, which is what
/// the example is for.

/// Drives the overlay from our own trigger (the AppBar bug button), on top of
/// the draggable launcher.
final debug = DevtrayController();

/// The one interceptor is all the Network page needs — every request made
/// through this client shows up, including the ones the app makes on its own.
final dio = Dio()..interceptors.add(DebugDioInterceptor());

/// The same, for `package:http`. Both transports feed one page.
final httpClient = DebugHttpClient(http.Client());

/// Live state sources, so the State page has something to watch.
final counter = CounterCubit();
final todos = TodoBloc();
