import '../../core/debug_overlay_kill_switch.dart';
import 'mock_rule.dart';
import 'mock_store.dart';

/// What an adapter should do with a request, decided once so dio and http can't
/// drift apart.
sealed class MockDecision {
  const MockDecision();
}

/// Let it hit the real server. [delay] is applied first when non-null.
class PassThrough extends MockDecision {
  final Duration? delay;
  const PassThrough({this.delay});
}

/// Return a faked response without contacting the server.
class RespondWith extends MockDecision {
  final int statusCode;
  final dynamic body;
  final Map<String, String> headers;
  final Duration? delay;

  const RespondWith({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.delay,
  });
}

/// Fail as if the network were unreachable — a connection error, not a status.
class FailWith extends MockDecision {
  final String message;
  final Duration? delay;
  const FailWith({required this.message, this.delay});
}

/// Decides what happens to a request. Both adapters call this.
///
/// The global offline switch beats everything; otherwise the first enabled rule
/// that matches wins.
MockDecision decideMock({
  required String url,
  required String method,
  MockStore? store,
}) {
  final s = store ?? MockStore.instance;

  // disable() must beat everything, including offline mode — it's the "I don't
  // want this feature" switch.
  // A mock rule intercepting real traffic in a release build would be the worst
  // failure this package could produce, so the global switch beats everything.
  if (!DebugOverlayKillSwitch.enabled) return const PassThrough();
  if (s.isDisabled) return const PassThrough();

  if (s.offline.value) {
    return const FailWith(message: 'Offline mode is on (debug_overlay)');
  }

  final rule = s.ruleFor(url: url, method: method);
  if (rule == null) return const PassThrough();

  return switch (rule.action) {
    MockAction.delayOnly => PassThrough(delay: rule.delay),
    MockAction.fail => FailWith(message: rule.failureMessage, delay: rule.delay),
    MockAction.respond => RespondWith(
        statusCode: rule.statusCode,
        body: rule.decodedBody,
        headers: rule.headers,
        delay: rule.delay,
      ),
  };
}

/// Label attached to a mocked entry's extras, so the Network list can badge it.
///
/// A faked response that looks identical to a real one will cost you an
/// afternoon. Everything mocked is marked.
const String kMockedExtraLabel = 'Mocked';
