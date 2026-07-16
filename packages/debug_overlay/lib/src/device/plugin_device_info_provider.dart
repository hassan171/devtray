import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'device_info_provider.dart';

/// Real device, OS and app-version facts, via `device_info_plus` and
/// `package_info_plus`.
///
/// ```dart
/// const DeviceDebugPage(provider: PluginDeviceInfoProvider())
/// ```
///
/// Each platform exposes a different set of fields, so this picks the handful
/// that actually matter in a bug report rather than dumping everything.
class PluginDeviceInfoProvider extends DeviceInfoProvider {
  const PluginDeviceInfoProvider();

  @override
  Future<List<DeviceInfoSection>> load() async {
    return [
      ...await const RuntimeDeviceInfoProvider().load(),
      await _appSection(),
      await _deviceSection(),
    ];
  }

  Future<DeviceInfoSection> _appSection() async {
    final info = await PackageInfo.fromPlatform();
    return DeviceInfoSection('App', {
      'Name': info.appName,
      'Package': info.packageName,
      'Version': info.version,
      'Build': info.buildNumber,
    });
  }

  Future<DeviceInfoSection> _deviceSection() async {
    final plugin = DeviceInfoPlugin();

    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      return DeviceInfoSection('Browser', {
        'Browser': web.browserName.name,
        'Platform': web.platform ?? '-',
        'User agent': web.userAgent ?? '-',
      });
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => await _android(plugin),
      TargetPlatform.iOS => await _ios(plugin),
      TargetPlatform.windows => await _windows(plugin),
      TargetPlatform.macOS => await _macos(plugin),
      TargetPlatform.linux => await _linux(plugin),
      TargetPlatform.fuchsia => const DeviceInfoSection('Device', {'Platform': 'fuchsia'}),
    };
  }

  Future<DeviceInfoSection> _android(DeviceInfoPlugin p) async {
    final i = await p.androidInfo;
    return DeviceInfoSection('Device', {
      'Model': '${i.manufacturer} ${i.model}',
      'Device': i.device,
      'Android': '${i.version.release} (SDK ${i.version.sdkInt})',
      'Physical device': i.isPhysicalDevice.toString(),
      'ABIs': i.supportedAbis.join(', '),
    });
  }

  Future<DeviceInfoSection> _ios(DeviceInfoPlugin p) async {
    final i = await p.iosInfo;
    return DeviceInfoSection('Device', {
      'Model': i.utsname.machine,
      'Name': i.name,
      'iOS': '${i.systemName} ${i.systemVersion}',
      'Physical device': i.isPhysicalDevice.toString(),
    });
  }

  Future<DeviceInfoSection> _windows(DeviceInfoPlugin p) async {
    final i = await p.windowsInfo;
    return DeviceInfoSection('Device', {
      'Computer': i.computerName,
      'Windows': '${i.productName} (build ${i.buildNumber})',
      'Cores': i.numberOfCores.toString(),
      'Memory': '${i.systemMemoryInMegabytes} MB',
    });
  }

  Future<DeviceInfoSection> _macos(DeviceInfoPlugin p) async {
    final i = await p.macOsInfo;
    return DeviceInfoSection('Device', {
      'Model': i.model,
      'Computer': i.computerName,
      'macOS': '${i.majorVersion}.${i.minorVersion}.${i.patchVersion}',
      'Arch': i.arch,
      'Memory': '${(i.memorySize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB',
    });
  }

  Future<DeviceInfoSection> _linux(DeviceInfoPlugin p) async {
    final i = await p.linuxInfo;
    return DeviceInfoSection('Device', {
      'Name': i.prettyName,
      'Version': i.version ?? '-',
      'Machine ID': i.machineId ?? '-',
    });
  }
}
