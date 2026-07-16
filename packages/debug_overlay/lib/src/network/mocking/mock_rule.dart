import 'dart:convert';

/// What a matched request should do instead of hitting the network.
enum MockAction {
  /// Return [MockRule.response] without contacting the server.
  respond,

  /// Fail as if the network were unreachable — a connection error, not an HTTP
  /// status. This is what "simulate offline" produces.
  fail,

  /// Hit the real server, but only after [MockRule.delay]. Use to surface
  /// loading states and race conditions.
  delayOnly,
}

/// A single interception rule: match a request, then delay / fake / fail it.
///
/// Rules are held on [MockStore] and consulted by the adapters on every
/// request. The first enabled rule that matches wins.
class MockRule {
  final String id;

  /// Matched against the full request URL. A plain substring by default;
  /// treated as a regular expression when [isRegex] is set.
  final String urlPattern;
  final bool isRegex;

  /// Restrict to one HTTP method. Null matches any.
  final String? method;

  final MockAction action;

  /// Applied before responding, for every action. Null means no delay.
  final Duration? delay;

  /// The faked response. Only used when [action] is [MockAction.respond].
  final int statusCode;
  final String? body;
  final Map<String, String> headers;

  /// Message on the synthesised failure, for [MockAction.fail].
  final String failureMessage;

  final bool enabled;

  const MockRule({
    required this.id,
    required this.urlPattern,
    this.isRegex = false,
    this.method,
    this.action = MockAction.respond,
    this.delay,
    this.statusCode = 200,
    this.body,
    this.headers = const {'content-type': 'application/json'},
    this.failureMessage = 'Simulated network failure (debug_overlay)',
    this.enabled = true,
  });

  /// True when this rule should intercept the given request.
  ///
  /// An invalid regex never matches — a half-typed pattern in the editor must
  /// not throw on every request in flight.
  bool matches({required String url, required String method}) {
    if (!enabled) return false;
    if (this.method != null && this.method!.toUpperCase() != method.toUpperCase()) return false;
    if (urlPattern.isEmpty) return false;

    if (!isRegex) return url.contains(urlPattern);

    try {
      return RegExp(urlPattern).hasMatch(url);
    } on FormatException {
      return false;
    }
  }

  /// The body as the adapters should hand it back: decoded JSON when it parses,
  /// otherwise the raw string.
  dynamic get decodedBody {
    final b = body;
    if (b == null || b.isEmpty) return null;
    try {
      return jsonDecode(b);
    } catch (_) {
      return b;
    }
  }

  MockRule copyWith({
    String? urlPattern,
    bool? isRegex,
    String? Function()? method,
    MockAction? action,
    Duration? Function()? delay,
    int? statusCode,
    String? Function()? body,
    Map<String, String>? headers,
    String? failureMessage,
    bool? enabled,
  }) {
    return MockRule(
      id: id,
      urlPattern: urlPattern ?? this.urlPattern,
      isRegex: isRegex ?? this.isRegex,
      method: method == null ? this.method : method(),
      action: action ?? this.action,
      delay: delay == null ? this.delay : delay(),
      statusCode: statusCode ?? this.statusCode,
      body: body == null ? this.body : body(),
      headers: headers ?? this.headers,
      failureMessage: failureMessage ?? this.failureMessage,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'urlPattern': urlPattern,
        'isRegex': isRegex,
        'method': method,
        'action': action.name,
        'delayMs': delay?.inMilliseconds,
        'statusCode': statusCode,
        'body': body,
        'headers': headers,
        'failureMessage': failureMessage,
        'enabled': enabled,
      };

  factory MockRule.fromJson(Map<String, dynamic> json) {
    final delayMs = json['delayMs'] as int?;
    return MockRule(
      id: json['id'] as String,
      urlPattern: json['urlPattern'] as String? ?? '',
      isRegex: json['isRegex'] as bool? ?? false,
      method: json['method'] as String?,
      action: MockAction.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => MockAction.respond,
      ),
      delay: delayMs == null ? null : Duration(milliseconds: delayMs),
      statusCode: json['statusCode'] as int? ?? 200,
      body: json['body'] as String?,
      headers: (json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      failureMessage: json['failureMessage'] as String? ?? 'Simulated network failure (debug_overlay)',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// Short human-readable summary of what the rule does — shown on the rule row.
  String get summary => switch (action) {
        MockAction.respond => 'HTTP $statusCode$_delaySuffix',
        MockAction.fail => 'Fail$_delaySuffix',
        MockAction.delayOnly => 'Pass through$_delaySuffix',
      };

  String get _delaySuffix {
    final d = delay;
    if (d == null || d == Duration.zero) return '';
    return ' · ${d.inMilliseconds}ms delay';
  }
}
