import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lost_mvp/main.dart';
import 'package:lost_mvp/app_language.dart';

class TestPaths extends PathProviderPlatform {
  TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var online = true;
  var loseInsertResponse = false;
  final rows = <String, Map<String, dynamic>>{};
  var uploads = 0;
  const userId = '11111111-1111-4111-8111-111111111111';
  setUpAll(() {
    db = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((request) async {
        http.Response jsonResponse(String body, int status) => http.Response(
          body,
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );

        if (request.url.path.endsWith('/token')) {
          return jsonResponse(
            jsonEncode({
              'access_token': 'test-access-token',
              'refresh_token': 'test-refresh-token',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': userId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'test@example.com',
                'created_at': '2026-10-06T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/logout')) return jsonResponse('', 204);
        if (!online) throw const SocketException('offline');
        if (request.url.path.contains('/storage/')) {
          uploads++;
          return jsonResponse('{"Key":"finds/test.jpg"}', 200);
        }
        if (request.method == 'GET') {
          final id = request.url.queryParameters['id']!.substring(3);
          return jsonResponse(
            jsonEncode(
              rows.containsKey(id)
                  ? [
                      {'id': id},
                    ]
                  : [],
            ),
            200,
          );
        }
        if (request.method == 'POST') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          rows[data['id'] as String] = data;
          if (loseInsertResponse) {
            loseInsertResponse = false;
            throw const SocketException('response lost');
          }
          return jsonResponse('', 201);
        }
        return jsonResponse('', 204);
      }),
    );
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lost-test-');
    PathProviderPlatform.instance = TestPaths(dir.path);
    online = true;
    loseInsertResponse = false;
    rows.clear();
    uploads = 0;
    appLanguage.value = const Locale('ru');
    await db.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test',
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  tearDownAll(() => db.dispose());

  Future<File> prepare(File input) => input.copy('${input.path}.prepared');
  Future<PendingFind> queuePhoto() async {
    final source = File('${dir.path}/source.jpg');
    await source.writeAsBytes([1, 2, 3]);
    return savePendingPhoto(
      XFile(source.path),
      DateTime.utc(2026, 10, 6),
      null,
    );
  }

  test(
    'offline queue retains metadata and uploads once after reconnection',
    () async {
      final item = await queuePhoto();
      final before = jsonDecode(await item.meta.readAsString());
      online = false;
      await expectLater(
        uploadPendingPhotos(prepare: prepare),
        throwsA(isA<SocketException>()),
      );
      expect(await pendingFinds(), hasLength(1));
      expect(jsonDecode(await item.meta.readAsString())['id'], before['id']);
      online = true;
      expect(await uploadPendingPhotos(prepare: prepare), isTrue);
      expect(await pendingFinds(), isEmpty);
      expect(rows, hasLength(1));
      expect(rows.values.single['created_at'], '2026-10-06T00:00:00.000Z');
    },
  );

  test(
    'lost insert response does not duplicate a find or reupload its image',
    () async {
      await queuePhoto();
      loseInsertResponse = true;
      await expectLater(
        uploadPendingPhotos(prepare: prepare),
        throwsA(isA<SocketException>()),
      );
      expect(await pendingFinds(), hasLength(1));
      expect(rows, hasLength(1));
      await uploadPendingPhotos(prepare: prepare);
      expect(rows, hasLength(1));
      expect(uploads, 1);
      expect(await pendingFinds(), isEmpty);
    },
  );

  test('interface language survives reload independently of posters', () async {
    await setAppLanguage('az');
    appLanguage.value = const Locale('ru');
    await loadAppLanguage();
    expect(appLanguage.value.languageCode, 'az');
    expect(posters, hasLength(16));
  });

  testWidgets('printer opens 16 posters and a language opens its poster', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(bottomNavigationBar: AppNavBar()),
      ),
    );
    await tester.tap(find.byIcon(Icons.print_outlined));
    await tester.pumpAndSettle();
    expect(posters, hasLength(16));
    expect(find.text('ZH'), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsNothing);
    await tester.tap(find.text('ZH'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterPage), findsOneWidget);
    expect(find.text('LOST'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('公共交通機関'), findsNothing);
    expect(find.text('丢东西了吗？'), findsOneWidget);
    expect(find.text('扫描二维码并安装 LOST。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'support amounts contain numbers only including all large amounts',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SupportPage()));
      for (final amount in ['500', '1000', '2000', '5000', '10000']) {
        await tester.scrollUntilVisible(find.text(amount), 180);
        expect(find.text(amount), findsOneWidget);
      }
      expect(find.text(r'$1000'), findsNothing);
      expect(find.text(r'$10,000'), findsNothing);
    },
  );

  testWidgets('demo feed remains available and demo controls explain themselves', (tester) async {
    await db.auth.signOut(scope: SignOutScope.local);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const FeedPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FilmFrame), findsWidgets);
    expect(find.byType(SignInPage), findsNothing);
    await tester.tap(find.byIcon(Icons.front_hand).first);
    await tester.pumpAndSettle();
    expect(find.text('Это демонстрационный пример. Настоящие находки доступны после входа.'), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign-in offers Google without email entry', (tester) async {
    await db.auth.signOut(scope: SignOutScope.local);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SignInPage(),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
    expect(find.byIcon(Icons.g_mobiledata), findsNothing);
    final googleImage = tester.widget<Ink>(find.byType(Ink));
    expect((googleImage.decoration as BoxDecoration).image!.image, const AssetImage('assets/google_sign_in.png'));
    expect(find.byIcon(Icons.email_outlined), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
