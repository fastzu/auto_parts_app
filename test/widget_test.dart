import 'package:flutter_test/flutter_test.dart';
import 'package:auto_parts_app/main.dart';

void main() {
  testWidgets('App widget smoke test', (WidgetTester tester) async {
    expect(const AutoPartsSupabaseApp(), isNotNull);
  });
}
