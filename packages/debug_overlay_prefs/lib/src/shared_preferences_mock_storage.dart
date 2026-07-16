import 'package:debug_overlay/debug_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Persists mock rules in `shared_preferences`, so they survive a hot restart
/// and an app relaunch.
///
/// ```dart
/// void main() async {
///   MockStore.instance.storage = SharedPreferencesMockRuleStorage();
///   await MockStore.instance.load();
///   runDebugApp(const MyApp(), pages: const [NetworkDebugPage()]);
/// }
/// ```
class SharedPreferencesMockRuleStorage implements MockRuleStorage {
  static const _key = 'debug_overlay.mock_rules';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String json) async => (await SharedPreferences.getInstance()).setString(_key, json);
}
