import 'package:devtray/devtray.dart';
// Not exported from the barrel — the pane and formatters are internal to the
// Network page, and the barrel exports only `Devtray` itself from the facade.
import 'package:devtray/src/core/devtray_facade.dart';
import 'package:devtray/src/network/components/network_detail_pane.dart';
import 'package:devtray/src/network/components/network_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _request({Map<String, dynamic>? headers}) => DevtrayNet.instance.add(
  method: 'GET',
  uri: Uri.parse('https://api.test/orders'),
  requestHeaders:
      headers ??
      const {
        'authorization': 'Bearer token-123',
        'content-type': 'application/json',
        'user-agent': 'Dart/3.5',
        'accept-encoding': 'gzip',
      },
)!;

/// Applies a `configure` callback without going through [runDebugApp].
///
/// These tests are about the filter, not about launch ordering — and
/// `runDebugApp` hooks `debugPrint` and the error handlers, which a test then
/// has to unpick. [Devtray.network] is the surface under test either way.
void _configure(void Function(Devtray) body) => applyDevtraySetup(body);

/// Pumps the detail pane for [entry]. No theme wrapper — `DevtrayTheme.of`
/// falls back to the light default outside a scope.
Future<void> _pumpPane(WidgetTester tester, NetworkLogEntry entry) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NetworkDetailPane(entry: entry, onBack: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayLog.instance.clear();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear()
      ..hiddenHeaderNames.clear()
      ..hiddenHeaderPredicate = null
      ..hideAllHeaders = false
      ..headerHiding = HeaderHiding.mask;
  });

  group('the filter itself', () {
    test('nothing is hidden by default', () {
      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isFalse);
    });

    test('a named header is hidden', () {
      _configure((d) => d..network(hideHeaders: {'user-agent'}));

      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('authorization'), isFalse);
    });

    test('matching is case-insensitive in both directions', () {
      // HTTP header names are case-insensitive; a Dart Set is not. Neither the
      // casing configured nor the casing the transport captured should decide
      // the answer.
      _configure((d) => d..network(hideHeaders: {'User-Agent'}));

      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('USER-AGENT'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('User-Agent'), isTrue);
    });

    test('the predicate catches a family the set cannot enumerate', () {
      _configure((d) => d..network(hideHeader: (name) => name.startsWith('x-internal-')));

      expect(DevtrayNet.instance.isHeaderHidden('x-internal-trace'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('x-request-id'), isFalse);
    });

    test('the predicate receives the name already lowercased', () {
      String? seen;
      _configure((d) => d..network(hideHeader: (name) => (seen = name) == 'never'));

      DevtrayNet.instance.isHeaderHidden('X-Internal-Trace');
      expect(seen, 'x-internal-trace');
    });

    test('set and predicate both apply', () {
      _configure(
        (d) => d..network(hideHeaders: {'user-agent'}, hideHeader: (name) => name.startsWith('x-')),
      );

      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('x-trace'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('accept'), isFalse);
    });

    test('two calls accumulate rather than the last one winning', () {
      _configure(
        (d) => d
          ..network(hideHeaders: {'user-agent'})
          ..network(hideHeaders: {'accept-encoding'}),
      );

      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('accept-encoding'), isTrue);
    });

    test('hideAllHeaders hides every name, listed or not', () {
      _configure((d) => d..network(hideAllHeaders: true));

      expect(DevtrayNet.instance.isHeaderHidden('authorization'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('content-type'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('anything-at-all'), isTrue);
    });

    test('hideAllHeaders wins over a narrower set or predicate', () {
      // The blanket flag should not have to agree with a set that names only
      // some headers — it means "all", and all is what it does.
      _configure(
        (d) => d..network(hideHeaders: {'user-agent'}, hideAllHeaders: true),
      );

      expect(DevtrayNet.instance.isHeaderHidden('user-agent'), isTrue);
      expect(DevtrayNet.instance.isHeaderHidden('authorization'), isTrue);
    });
  });

  group('capture keeps the value; only what leaves is masked', () {
    const mask = DevtrayNet.redactionMask;

    test('the live entry still holds the real value in memory', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}));

      // Redaction governs what leaves the entry, not what is captured — the
      // pane reads the live map through redactHeaders, but the map itself is
      // intact so nothing downstream is starved of it.
      expect(_request().requestHeaders['authorization'], 'Bearer token-123');
    });

    test('cURL masks the value but keeps the header', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}));
      final e = _request();

      final curl = buildCurl(
        method: e.method,
        uri: e.uri,
        headers: DevtrayNet.instance.redactHeaders(e.requestHeaders),
        data: e.requestBody,
      );
      expect(curl, contains("-H 'authorization: $mask'"));
      expect(curl, isNot(contains('Bearer token-123')));
    });

    test('toJson masks the value', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}));

      final json = _request().toJson()['requestHeaders'] as Map;
      expect(json['authorization'], mask);
      expect(json.keys, contains('authorization'), reason: 'the name is kept, so a reader sees it WAS sent');
    });

    test('hideAllHeaders masks every value across cURL and export', () {
      _configure((d) => d..network(hideAllHeaders: true));
      final e = _request();

      final json = e.toJson()['requestHeaders'] as Map;
      expect(json.values, everyElement(mask));
      final curl = buildCurl(
        method: e.method,
        uri: e.uri,
        headers: DevtrayNet.instance.redactHeaders(e.requestHeaders),
        data: e.requestBody,
      );
      expect(curl, isNot(contains('Bearer token-123')));
      expect(curl, isNot(contains('Dart/3.5')));
    });
  });

  group('redactHeaders', () {
    const mask = DevtrayNet.redactionMask;

    test('masks named request headers, keeps the rest verbatim', () {
      _configure((d) => d..network(hideHeaders: {'authorization', 'accept-encoding'}));

      final rendered = prettyMap(DevtrayNet.instance.redactHeaders(_request().requestHeaders));
      expect(rendered, contains('authorization: $mask'));
      expect(rendered, contains('accept-encoding: $mask'));
      expect(rendered, contains('content-type: application/json'));
      expect(rendered, isNot(contains('Bearer token-123')));
    });

    test('masks named response headers', () {
      _configure((d) => d..network(hideHeaders: {'set-cookie'}));

      final rendered = prettyHeaders(
        DevtrayNet.instance.redactResponseHeaders(const {
          'content-type': ['application/json'],
          'set-cookie': ['session=abc'],
        }),
      );
      expect(rendered, contains('content-type: application/json'));
      expect(rendered, contains('set-cookie: $mask'));
      expect(rendered, isNot(contains('session=abc')));
    });

    test('returns the same map instance when nothing is configured', () {
      // The common no-redaction path must allocate nothing — the map is read
      // per header per rebuild.
      final headers = _request().requestHeaders;
      expect(identical(DevtrayNet.instance.redactHeaders(headers), headers), isTrue);
    });

    test('an empty map is returned untouched', () {
      _configure((d) => d..network(hideAllHeaders: true));
      expect(DevtrayNet.instance.redactHeaders(const {}), isEmpty);
    });
  });

  group('HeaderHiding.omit drops the header entirely', () {
    test('the header is gone from the rendered request, name and all', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}, headerHiding: HeaderHiding.omit));

      final out = DevtrayNet.instance.redactHeaders(_request().requestHeaders);
      expect(out.containsKey('authorization'), isFalse);
      expect(out.containsKey('content-type'), isTrue, reason: 'unhidden headers stay');
      // Neither the value nor the mask — omit means it was never there.
      final rendered = prettyMap(out);
      expect(rendered, isNot(contains('authorization')));
      expect(rendered, isNot(contains(DevtrayNet.redactionMask)));
    });

    test('omit reaches cURL and export too', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}, headerHiding: HeaderHiding.omit));
      final e = _request();

      final json = e.toJson()['requestHeaders'] as Map;
      expect(json.containsKey('authorization'), isFalse);
      final curl = buildCurl(
        method: e.method,
        uri: e.uri,
        headers: DevtrayNet.instance.redactHeaders(e.requestHeaders),
        data: e.requestBody,
      );
      expect(curl, isNot(contains('authorization')));
      expect(curl, isNot(contains('Bearer token-123')));
    });

    test('omit on the response side drops the entry', () {
      _configure((d) => d..network(hideHeaders: {'set-cookie'}, headerHiding: HeaderHiding.omit));

      final out = DevtrayNet.instance.redactResponseHeaders(const {
        'content-type': ['application/json'],
        'set-cookie': ['session=abc'],
      });
      expect(out.containsKey('set-cookie'), isFalse);
      expect(out.containsKey('content-type'), isTrue);
    });

    test('hideAllHeaders + omit leaves an empty header map', () {
      _configure((d) => d..network(hideAllHeaders: true, headerHiding: HeaderHiding.omit));

      expect(DevtrayNet.instance.redactHeaders(_request().requestHeaders), isEmpty);
    });
  });

  group('detail pane', () {
    testWidgets('a hidden header shows its name with a masked value', (tester) async {
      _configure((d) => d..network(hideHeaders: {'authorization'}));
      await _pumpPane(tester, _request());

      expect(find.textContaining('content-type: application/json'), findsOneWidget);
      // The token is gone from the pane, but the reader still sees it was sent.
      expect(find.textContaining('Bearer token-123'), findsNothing);
      expect(find.textContaining('authorization: ${DevtrayNet.redactionMask}'), findsOneWidget);
    });

    testWidgets('with no filter configured every header shows verbatim', (tester) async {
      await _pumpPane(tester, _request());

      expect(find.textContaining('user-agent: Dart/3.5'), findsOneWidget);
    });
  });

  group('the bug report', () {
    test('masks a redacted header — the report is what a user pastes into a ticket', () {
      _configure((d) => d..network(hideHeaders: {'authorization'}));
      _request();

      final report = DebugReport.build();
      expect(report, contains('authorization'));
      expect(report, contains(DevtrayNet.redactionMask));
      expect(report, isNot(contains('Bearer token-123')));
    });
  });
}
