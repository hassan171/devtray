import 'package:flutter/foundation.dart';

/// A named group of `key: value` rows in the Device page.
class DeviceInfoSection {
  final String title;
  final Map<String, String> values;
  const DeviceInfoSection(this.title, this.values);
}

/// Supplies the sections shown on the Device page.
///
/// The built-in [PluginDeviceInfoProvider] covers device, OS and app version.
/// Implement this to add your own — build flavor, backend URL, logged-in user,
/// feature flags — or to replace it entirely if you'd rather not take the
/// `device_info_plus` / `package_info_plus` dependencies.
abstract class DeviceInfoProvider {
  const DeviceInfoProvider();

  /// Called once when the page is first shown.
  Future<List<DeviceInfoSection>> load();
}

/// Merges several providers into one page. The app's own sections are usually
/// the interesting ones, so pass them first.
class CompositeDeviceInfoProvider extends DeviceInfoProvider {
  final List<DeviceInfoProvider> providers;
  const CompositeDeviceInfoProvider(this.providers);

  @override
  Future<List<DeviceInfoSection>> load() async {
    final results = await Future.wait(providers.map((p) => p.load()));
    return results.expand((s) => s).toList();
  }
}

/// A fixed set of sections — for values the app already knows.
///
/// ```dart
/// DeviceDebugPage(
///   provider: CompositeDeviceInfoProvider([
///     const PluginDeviceInfoProvider(),
///     StaticDeviceInfoProvider([
///       DeviceInfoSection('Environment', {'API': apiUrl, 'Flavor': flavor}),
///     ]),
///   ]),
/// )
/// ```
class StaticDeviceInfoProvider extends DeviceInfoProvider {
  final List<DeviceInfoSection> sections;
  const StaticDeviceInfoProvider(this.sections);

  @override
  Future<List<DeviceInfoSection>> load() async => sections;
}

/// Values that are always available, with no plugins: the Flutter/Dart build
/// mode and the compile-time platform.
class RuntimeDeviceInfoProvider extends DeviceInfoProvider {
  const RuntimeDeviceInfoProvider();

  @override
  Future<List<DeviceInfoSection>> load() async => [
        DeviceInfoSection('Runtime', {
          'Build mode': kDebugMode
              ? 'debug'
              : kProfileMode
                  ? 'profile'
                  : 'release',
          'Platform': defaultTargetPlatform.name,
          'Web': kIsWeb.toString(),
        }),
      ];
}
