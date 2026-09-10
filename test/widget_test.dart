import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/app.dart';

void main() {
  testWidgets('shows a startup state', (tester) async {
    await tester.pumpWidget(const SpotifinApp());
    expect(find.text('Spotifin'), findsNothing);
  }, skip: true);
}
