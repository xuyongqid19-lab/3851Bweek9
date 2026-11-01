import 'package:flutter_test/flutter_test.dart';
import 'package:global_village_app/main.dart';
import 'package:global_village_app/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Login page is shown at startup when not signed in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const GlobalVillageApp());
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Login'), findsAtLeastNWidgets(1));
    expect(find.text('No account? Register'), findsOneWidget);
  });
}
