import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void main() {
  runApp(const P());
}

class P extends StatefulWidget {
  const P({super.key});
  @override State<P> createState() => _S();
}

class _S extends State<P> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        const MaterialApp(home: Scaffold(body: Center(child: Text('APP')))),
        Positioned(
          right: 20, bottom: 20,
          child: Material(
            child: ElevatedButton(
              onPressed: () {
                debugPaintSizeEnabled = !debugPaintSizeEnabled;
                int n = 0;
                late RenderObjectVisitor v;
                v = (RenderObject c) { n++; c.markNeedsPaint(); c.visitChildren(v); };
                for (final rv in RendererBinding.instance.renderViews) { rv.visitChildren(v); }
                debugPrint('PROBE: flag=$debugPaintSizeEnabled marked=$n renderViews=${RendererBinding.instance.renderViews.length}');
                setState(() {});
              },
              child: const Text('toggle'),
            ),
          ),
        ),
      ],
    );
  }
}
