import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Riverpod provider, living alongside the example's bloc cubits on purpose.
///
/// The State page shows **both** — it reads from `StateInspector`, which knows
/// about neither library. `debug_overlay_bloc` and `debug_overlay_riverpod` are
/// each ~50 lines of glue pushing into the same API, and installing both is what
/// an app mid-migration actually needs.
///
/// Named (`name: 'session'`) so the page has something readable to show. Without
/// it the row falls back to the runtime type, which is noisier and says less.
class Session extends Notifier<String> {
  @override
  String build() => 'anonymous';

  /// Fields the notifier holds *outside* its state — the case
  /// `StateInspector.inspect` exists for. Riverpod's `state` is protected
  /// (unlike a bloc's, which is public), so an extractor can't read it from
  /// outside; these are the notifier's own, and it can expose whatever it likes.
  int signIns = 0;
  DateTime? lastSignIn;

  void signIn(String user) {
    state = user;
    signIns++;
    lastSignIn = DateTime.now();
  }

  void signOut() => state = 'anonymous';
}

final sessionProvider = NotifierProvider<Session, String>(Session.new, name: 'session');
