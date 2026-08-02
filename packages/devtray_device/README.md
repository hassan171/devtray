# devtray_device

Real device, OS and app facts for devtray's **Device** page.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the device_info_plus + package_info_plus glue.

## Install

```yaml
dependencies:
  devtray: ^0.6.2
  devtray_device: ^0.6.2
```

## Usage

```dart
import 'package:devtray_device/devtray_device.dart';

DeviceDebugPage(provider: PluginDeviceInfoProvider())
```

The core's Device page has no plugin dependencies of its own, so without a provider it shows nothing. This fills it in with the real model, OS version and app version.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
