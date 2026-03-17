// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:agri_logistic_platform/main.dart';

void main() {
  testWidgets('auth flow opens role and login pages', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartAgriPlatform());

    expect(find.text('Smart Agri Logistics'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);

    await tester.tap(find.text('Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Select your role to continue'), findsOneWidget);
    expect(find.text('Farmer'), findsOneWidget);
    expect(find.text('Transporter'), findsOneWidget);
    expect(find.text('Retailer'), findsOneWidget);

    await tester.tap(find.text('Farmer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('FARMER'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    RealtimeService.instance.stop();
    await tester.pump(const Duration(seconds: 13));
  });
}
