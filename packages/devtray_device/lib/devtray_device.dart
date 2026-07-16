/// Real device facts for `devtray`'s Device page.
///
/// ```dart
/// DeviceDebugPage(provider: PluginDeviceInfoProvider())
/// ```
///
/// The core's default provider needs no plugins, but only knows the build mode
/// and platform. This one adds the things you actually end up asking for in a
/// bug report — device model, OS version, app version — via `device_info_plus`
/// and `package_info_plus`.
///
/// Merge it with your own sections; it's just a `DeviceInfoProvider`:
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
library;

export 'src/plugin_device_info_provider.dart';
