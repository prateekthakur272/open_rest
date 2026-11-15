// ignore_for_file: constant_identifier_names
import 'package:flutter/widgets.dart';
import 'package:open_rest/components/text.dart';
import 'package:open_rest/theme/theme.dart';

String _shortMethod(String m) {
  switch (m.toUpperCase()) {
    case 'DELETE':
      return 'DEL';
    case 'OPTIONS':
      return 'OPT';
    case 'PATCH':
      return 'PATCH';
    default:
      return m.toUpperCase();
  }
}

/// Width of the method label in tree rows; workflow rows use the same slot for their icon so the titles line up.
const double METHOD_SLOT = 33;

/// Colored label showing an HTTP method.
class MethodPill extends StatelessWidget {
  const MethodPill(this.method, {super.key});

  final String method;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: METHOD_SLOT,
      child: Align(
        heightFactor: 1,
        alignment: Alignment.centerLeft,
        child: T(
          _shortMethod(method),
          color: methodColor(method, p),
          size: 10,
          weight: FontWeight.w700,
          maxLines: 1,
          overflow: TextOverflow.visible,
          softWrap: false,
        ),
      ),
    );
  }
}
