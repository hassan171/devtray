import 'package:devtray/devtray.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cart {
  final int items;
  _Cart(this.items);
}

void main() {
  // The point of exporting them: an app can name these shapes in its own code —
  // a field, a parameter, a variable — not just pass a literal at the call site.
  test('the typedefs are usable from outside the package', () {
    const DevtrayEnricher enricher = _currentScreen;
    const DevtrayInspector<_Cart> inspector = _cartFields;
    const DevtrayFormatter<_Cart> formatter = _renderCart;
    const DevtrayConfigure configure = _setUp;

    expect(enricher(), {'screen': 'home'});
    expect(inspector(_Cart(3)), {'items': 3});
    expect(formatter(_Cart(3)), '3 items');
    expect(configure, isNotNull);
  });
}

Map<String, Object?> _currentScreen() => {'screen': 'home'};
Map<String, Object?> _cartFields(_Cart c) => {'items': c.items};
String _renderCart(_Cart c) => '${c.items} items';
void _setUp(Devtray devtray) => devtray.excludeUrls(const ['/health']);
