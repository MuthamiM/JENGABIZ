import 'package:duka_ledger/screens/auth_screen.dart';
import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remote API configuration requires HTTPS', () {
    expect(
      () => JengaApiService.instance.configure(url: 'http://api.example.com'),
      throwsArgumentError,
    );
    JengaApiService.instance.configure(url: 'https://api.example.com');
  });

  test('OTP request, resend, and verification use email-only routes', () async {
    final received = <Map<String, dynamic>>[];
    final api = JengaApiService.forTesting((uri, payload) async {
      received.add({'path': uri.path, ...payload});
      return JengaApiResponse(200, {
        'success': true,
        if (uri.path.endsWith('verify-otp')) ...{
          'verified': true,
          'verificationToken': 'one-time-verification-grant',
        },
      });
    });
    api.configure(url: 'https://jengabiz-api.mftechnologies.org');

    expect(
      (await api.requestEmailOtp(' Owner@example.com '))?['success'],
      isTrue,
    );
    expect(
      (await api.requestEmailOtp('owner@example.com'))?['success'],
      isTrue,
    );
    expect(
      await api.verifyEmailOtp('owner@example.com', '123456'),
      'one-time-verification-grant',
    );

    expect(received.map((request) => request['path']).toList(), [
      '/email-auth/request-otp',
      '/email-auth/request-otp',
      '/email-auth/verify-otp',
    ]);
    expect(received.every((request) => request.containsKey('email')), isTrue);
    expect(received.every((request) => !request.containsKey('phone')), isTrue);
    expect(received.map((request) => request['email']).toSet(),
        {'owner@example.com'});
  });

  test('account creation and sign-in use the existing secure API route',
      () async {
    final paths = <String>[];
    final api = JengaApiService.forTesting((uri, payload) async {
      paths.add(uri.path);
      if (uri.path.endsWith('/login')) {
        return const JengaApiResponse(401, {
          'success': false,
          'message': 'Email or password is incorrect.',
        });
      }
      return const JengaApiResponse(201, {'success': true});
    });
    api.configure(url: 'https://jengabiz-api.mftechnologies.org');

    final login = await api.loginAccount('Owner@example.com', 'password123');
    expect(login?.statusCode, 401);
    expect(login?.succeeded, isFalse);

    final created = await api.createAccount(
      email: 'owner@example.com',
      verificationToken: 'single-use-proof',
      name: 'Owner',
      shopName: 'Main Shop',
      phone: '',
      password: 'password123',
      items: const [],
      migrate: true,
    );
    expect(created?.succeeded, isTrue);
    expect(paths, [
      '/email-auth/login',
      '/email-auth/migrate',
    ]);
  });

  test('saved-session restoration requests the signed-in profile', () async {
    final requests = <Map<String, Object?>>[];
    final api = JengaApiService.forTestingRequests((method, uri, _) async {
      requests.add({'method': method, 'path': uri.path});
      return const JengaApiResponse(200, {'success': true, 'user': {}});
    });
    api.configure(url: 'https://jengabiz-api.mftechnologies.org');

    expect((await api.fetchAccountProfile())?.succeeded, isTrue);
    expect(requests, [
      {
        'method': 'GET',
        'path': '/email-auth/me',
      },
    ]);
  });

  test(
      'password sign-in stores only a salted hash and rejects a wrong password',
      () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp',
    );
    final db = JengaDB.instance;
    db.users = [];
    db.currentUser = null;
    db.items = [];
    db.inventoryOwnerId = null;

    final user = await db.createAccount(
      name: 'QA User',
      shopName: 'QA Shop',
      phone: '+254700000000',
      email: 'qa@example.com',
      password: 'correct horse battery',
    );

    expect(user.passwordHash, isNotNull);
    expect(user.passwordHash, isNot('correct horse battery'));
    expect(await db.login(user.email, 'incorrect password'), isFalse);
    expect(await db.login(user.email, 'correct horse battery'), isTrue);
  });

  testWidgets('sign-in offers email, password, and consent policy links',
      (tester) async {
    final db = JengaDB.instance;
    db.users = [
      JengaUser(
        id: 'qa-login',
        name: 'QA User',
        shopName: 'QA Shop',
        phone: '+254700000000',
        email: 'qa@example.com',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(onSuccess: () {}, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Read:'), findsOneWidget);
    expect(find.text('Touch Sensor'), findsNothing);
    expect(find.textContaining('Musa'), findsNothing);

    await tester.tap(find.text('Terms of Use'));
    await tester.pumpAndSettle();
    expect(find.textContaining('JengaBiz is provided by MF Technologies'),
        findsOneWidget);
  });

  testWidgets(
      'switching an existing local profile to new account clears old details',
      (tester) async {
    JengaDB.instance.users = [
      JengaUser(
        id: 'existing-user',
        name: 'Existing User',
        shopName: 'Existing Shop',
        phone: '+254700000000',
        email: 'existing@example.com',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(onSuccess: () {}, onBack: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Account'));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(6));
    expect(fields.every((field) => field.controller?.text.isEmpty ?? true),
        isTrue);
    expect(find.text('Country'), findsNothing);
    expect(find.text('County / Region'), findsNothing);
    expect(find.text('Phone Number (optional)'), findsOneWidget);
    expect(find.text('Create Account & Verify Email'), findsOneWidget);
  });
}
