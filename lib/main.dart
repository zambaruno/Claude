import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_language.dart';
import 'support_payments.dart';
export 'support_payments.dart';

import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
// Permanent link printed as a QR code on posters: the Play Store page of this app.
const appLink = String.fromEnvironment(
  'LOST_APP_LINK',
  defaultValue: 'https://www.zambaru.com/lost-app',
);
// Web OAuth client ID enables the native Google account picker.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const authCallback = 'com.zambaruno.lost://login-callback/';
const appVersion = '0.3.0';
// Flat light palette that matches the red emblem.
const brandRed = Color(0xffc81e1e);
const acceptGreen = Color(0xff1f9d55);
const paper = Color(0xfffefefe);
const ink = Color(0xff202124);
const mist = Color(0xfff1f1f1);
const buildNumber = String.fromEnvironment('LOST_BUILD_NUMBER', defaultValue: 'local');
const buildCommit = String.fromEnvironment('LOST_BUILD_COMMIT', defaultValue: 'local');

void showBuildInfo(BuildContext context) => showAboutDialog(
  context: context,
  applicationName: 'LOST',
  applicationVersion: '$appVersion ($buildNumber) · ${buildCommit.length > 7 ? buildCommit.substring(0, 7) : buildCommit}',
  applicationIcon: Image.asset('assets/lost_logo.png', width: 48, height: 48),
);
// Enable each entry only after the matching Supabase provider and redirect are configured.
const googleAuthReady = bool.fromEnvironment(
  'GOOGLE_AUTH_READY',
  defaultValue: false,
);
const appleAuthReady = bool.fromEnvironment(
  'APPLE_AUTH_READY',
  defaultValue: false,
);
const phoneAuthReady = bool.fromEnvironment(
  'PHONE_AUTH_READY',
  defaultValue: false,
);
late final SupabaseClient db;
// Global navigator so the brand mark overlay can open pages from anywhere.
final navigatorKey = GlobalKey<NavigatorState>();
bool _fdOpen = false;
void openFreeDiagnostic() {
  if (_fdOpen) return;
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  _fdOpen = true;
  nav
      .push(
        MaterialPageRoute<void>(builder: (_) => const FreeDiagnosticPage()),
      )
      .then((_) => _fdOpen = false);
}
Position? selectedPosition;
const maxPhotoBytes = 2 * 1024 * 1024;

class PendingFind {
  const PendingFind(this.photo, this.meta);
  final File photo;
  final File meta;
}

Future<Directory> pendingFindsDirectory() async {
  final dir = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/pending-finds',
  );
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<List<PendingFind>> pendingFinds() async {
  final dir = await pendingFindsDirectory();
  final photos = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('.jpg'))
      .cast<File>()
      .toList();
  photos.sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final photo in photos)
      PendingFind(photo, File(photo.path.replaceAll('.jpg', '.json'))),
  ];
}

Future<Position?> capturePosition() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever)
      return null;
    return await Geolocator.getCurrentPosition(
      timeLimit: const Duration(seconds: 8),
    );
  } catch (_) {
    return null;
  }
}

// Accepted finds are stored as separate local records so several photos can be
// captured offline without one overwriting another.
Future<PendingFind> savePendingPhoto(
  XFile photo,
  DateTime capturedAt,
  Position? position,
) async {
  final dir = await pendingFindsDirectory();
  final id = '${capturedAt.toUtc().microsecondsSinceEpoch}';
  final pending = File('${dir.path}/$id.jpg');
  final stagedPhoto = await File(photo.path).copy('${pending.path}.tmp');
  final meta = File('${dir.path}/$id.json');
  await meta.writeAsString(
    jsonEncode({
      'id': newFindId(),
      'finder_id': db.auth.currentUser?.id,
      'captured_at': capturedAt.toUtc().toIso8601String(),
      'latitude': position?.latitude,
      'longitude': position?.longitude,
    }),
    flush: true,
  );
  await stagedPhoto.rename(pending.path);
  return PendingFind(pending, meta);
}

Future<File> preparePhoto(File input) async {
  final out = File(
    '${(await getTemporaryDirectory()).path}/find-${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  for (final quality in [80, 68, 55, 40]) {
    final bytes = await FlutterImageCompress.compressWithFile(
      input.path,
      minWidth: 1600,
      minHeight: 1600,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    if (bytes == null) throw StateError('Не удалось обработать фотографию');
    await out.writeAsBytes(bytes, flush: true);
    if (bytes.length <= maxPhotoBytes) return out;
  }
  throw StateError('Фотография больше 2 МБ. Сделайте другой снимок.');
}

Future<bool>? activePendingUpload;
Future<bool> uploadPendingPhotos({
  Future<File> Function(File) prepare = preparePhoto,
}) {
  if (activePendingUpload != null) return activePendingUpload!;
  final operation = _uploadPendingPhotos(prepare);
  activePendingUpload = operation;
  operation.then(
    (_) => activePendingUpload = null,
    onError: (Object _) => activePendingUpload = null,
  );
  return operation;
}

String newFindId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final queueChanges = ValueNotifier<int>(0);
Future<bool> _uploadPendingPhotos(Future<File> Function(File) prepare) async {
  final user = db.auth.currentUser;
  if (user == null) return false;
  final queue = await pendingFinds();
  var uploadedAny = false;
  for (final item in queue) {
    if (db.auth.currentUser?.id != user.id) break;
    File? prepared;
    try {
      if (!await item.meta.exists())
        continue; // Do not send a record without its metadata.
      final meta = Map<String, dynamic>.from(
        jsonDecode(await item.meta.readAsString()) as Map,
      );
      if (meta['finder_id'] != null && meta['finder_id'] != user.id) continue;
      meta['finder_id'] = user.id;
      meta['id'] ??= newFindId();
      final stagedMeta = File('${item.meta.path}.tmp');
      await stagedMeta.writeAsString(jsonEncode(meta), flush: true);
      await stagedMeta.rename(item.meta.path);
      final id = meta['id'] as String;
      final path = '${user.id}/$id.jpg';
      // A stable ID recovers from a lost response after a successful insert.
      final existing = await db
          .from('finds')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      if (existing == null) {
        prepared = await prepare(item.photo);
        try {
          await db.storage
              .from('finds')
              .upload(
                path,
                prepared,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
        } on StorageException catch (e) {
          if (e.statusCode != '409' && e.error != 'Duplicate') rethrow;
        }
        if (db.auth.currentUser?.id != user.id) break;
        await db.from('finds').insert({
          'id': id,
          'finder_id': user.id,
          'image_path': path,
          'description': 'Фото',
          'status': 'held',
          'created_at': meta['captured_at'],
          'latitude': meta['latitude'],
          'longitude': meta['longitude'],
        });
      }
      await item.photo.delete();
      if (await item.meta.exists()) await item.meta.delete();
      uploadedAny = true;
      queueChanges.value++;
    } finally {
      if (prepared != null && await prepared.exists()) await prepared.delete();
    }
  }
  return uploadedAny;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Настройте SUPABASE_URL и SUPABASE_ANON_KEY. См. README.md.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
    authOptions: const FlutterAuthClientOptions(persistSession: true),
  );
  db = Supabase.instance.client;
  await loadAppLanguage();
  runApp(const LostApp());
}

class LostApp extends StatefulWidget {
  const LostApp({super.key});
  @override
  State<LostApp> createState() => _LostAppState();
}

class _LostAppState extends State<LostApp> with WidgetsBindingObserver {
  Timer? retryTimer;
  StreamSubscription<AuthState>? authSubscription;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    authSubscription = db.auth.onAuthStateChange.listen((state) {
      if (state.session != null) sync();
    }, onError: (Object _) {});
    retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    sync();
  }

  Future<void> sync() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
      return;
    try {
      await uploadPendingPhotos();
    } catch (_) {
      /* Keep the queue for the next retry. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: appLanguage,
    builder: (_, locale, child) => MaterialApp(
      title: 'LOST',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      locale: locale,
      supportedLocales: interfaceLanguages.keys.map((code) => Locale(code)),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandRed,
        ).copyWith(primary: brandRed, surface: paper),
        scaffoldBackgroundColor: paper,
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        useMaterial3: true,
      ),
      // A large, semi-transparent Free Diagnostic mark on every screen.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 6,
            child: GestureDetector(
              onTap: openFreeDiagnostic,
              child: Opacity(
                opacity: 0.85,
                child: Image.asset(
                  'assets/free_diagnostic_logo.png',
                  width: 104,
                  height: 104,
                ),
              ),
            ),
          ),
        ],
      ),
      home: const HomePage(),
    ),
  );
}

void toast(BuildContext c, String s) {
  if (c.mounted)
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));
}

Future<bool> ensureAuth(BuildContext c) async {
  if (db.auth.currentSession != null) return true;
  await Navigator.push(
    c,
    MaterialPageRoute(builder: (_) => const SignInPage()),
  );
  return db.auth.currentSession != null;
}

Future<void> takePhoto(BuildContext context) async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  if (photo == null || !context.mounted) return;
  final capturedAt = DateTime.now();
  final position = await capturePosition();
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PhotoReviewPage(
        photo: photo,
        capturedAt: capturedAt,
        position: position,
      ),
    ),
  );
}

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, this.signingIn = false, this.language = 'RU'});
  final bool signingIn;
  final String language;

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: paper,
      border: Border(top: BorderSide(color: Color(0xffe6e6e6))),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _icon(
              Icons.view_carousel_outlined,
              tr(context, 'Лента'),
              () => _open(context, const FeedPage()),
            ),
            _icon(
              Icons.print_outlined,
              tr(context, 'Язык плаката'),
              () => _open(context, const PosterLanguagesPage()),
            ),
            _lens(context),
            _icon(
              Icons.favorite_border,
              tr(context, 'Поддержать'),
              () => _open(context, const SupportPage()),
            ),
            _icon(
              Icons.person_outline,
              tr(context, 'Профиль'),
              () => _open(context, const ProfilePage()),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _icon(IconData icon, String hint, VoidCallback onTap) => IconButton(
    onPressed: onTap,
    tooltip: hint,
    iconSize: 28,
    color: ink,
    icon: Icon(icon),
  );

  Widget _lens(BuildContext context) => Semantics(
    label: tr(context, 'Камера'),
    button: true,
    child: Tooltip(
      message: tr(context, 'Камера'),
      child: InkWell(
        onTap: () => takePhoto(context),
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: LensHero(size: 56),
        ),
      ),
    ),
  );
}

// Open a Zambaru site inside a lightweight in-app browser that sits over
// the app, so the person stays one tap away from returning.
Future<void> openSite(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  } catch (_) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

// Shared top bar: LOST mark on the left, the home site on the right.
// Every path through the app visibly leads back to www.zambaru.com.
class ZambaruBar extends StatelessWidget implements PreferredSizeWidget {
  const ZambaruBar({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(52);
  @override
  Widget build(BuildContext context) => AppBar(
    titleSpacing: 12,
    title: Row(
      children: [
        Image.asset('assets/lost_logo.png', width: 26, height: 26),
        const SizedBox(width: 8),
        const Text(
          'LOST',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            fontSize: 17,
          ),
        ),
      ],
    ),
  );
}

// Provisional landing/download page for the Zambaruno Free Diagnostic app.
class FreeDiagnosticPage extends StatelessWidget {
  const FreeDiagnosticPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/free_diagnostic_logo.png',
                width: MediaQuery.sizeOf(context).width * .62,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              Text(
                tr(
                  context,
                  'Бесплатная диагностика бытовой и любой другой техники.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, height: 1.4),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  context,
                  'Приложение скоро будет доступно для скачивания.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: Colors.black54),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: brandRed,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 14,
                  ),
                ),
                onPressed: () => openSite('https://www.zambaruno.com'),
                icon: const Icon(Icons.download, size: 20),
                label: Text(tr(context, 'Скачать')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> beginPayment(PaymentSelection selection) async {
  final uri = supportPaymentUri(selection);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open checkout');
  }
}

String usdLabel(int amount) {
  final number = amount < 1000
      ? '$amount'
      : '${amount ~/ 1000},${(amount % 1000).toString().padLeft(3, '0')}';
  return r'$' + number;
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  int? selectedAmount;
  static const amounts = [
    1,
    2,
    3,
    5,
    10,
    20,
    50,
    100,
    500,
    1000,
    2000,
    5000,
    10000,
  ];

  Future<void> choose(PaymentMethod method) async {
    final amount = selectedAmount;
    if (amount == null) return;
    final selection = PaymentSelection(amount, method);
    try {
      await beginPayment(selection);
    } on PaymentSetupException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${selection.amountUsd}'),
          content: Text(tr(context, 'Приём платежей Zambaruno LLC ещё не подключён.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) toast(context, tr(context, 'Не удалось открыть оплату. Повторите попытку.'));
    }
  }

  Widget methodButton(PaymentMethod method, String label, IconData icon) =>
      OutlinedButton.icon(
        onPressed: () => choose(method),
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: ink),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.all(18),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final amount in amounts)
                  OutlinedButton(
                    onPressed: () => setState(() => selectedAmount = amount),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selectedAmount == amount
                          ? Colors.white
                          : ink,
                      backgroundColor: selectedAmount == amount
                          ? acceptGreen
                          : mist,
                    ),
                    child: Text(
                      '$amount',
                      style: const TextStyle(fontSize: 19),
                    ),
                  ),
              ],
            ),
          ),
          if (selectedAmount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Text(
                    '$selectedAmount',
                    style: const TextStyle(color: ink, fontSize: 26),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      methodButton(
                        PaymentMethod.googlePay,
                        'Google Pay',
                        Icons.account_balance_wallet_outlined,
                      ),
                      methodButton(
                        PaymentMethod.paypal,
                        'PayPal',
                        Icons.payments_outlined,
                      ),
                      methodButton(PaymentMethod.card, '💳', Icons.credit_card),
                      if (Platform.isIOS)
                        methodButton(
                          PaymentMethod.applePay,
                          'Apple Pay',
                          Icons.phone_iphone,
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class GeotagPage extends StatefulWidget {
  const GeotagPage({super.key});
  @override
  State<GeotagPage> createState() => _GeotagPageState();
}

class _GeotagPageState extends State<GeotagPage> {
  String state = selectedPosition == null ? '○' : '✓';
  Future<void> locate() async {
    if (selectedPosition != null) {
      selectedPosition = null;
      setState(() => state = '○');
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;
      final p = await Geolocator.getCurrentPosition();
      selectedPosition = p;
      if (mounted)
        setState(
          () => state =
              '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}',
        );
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    bottomNavigationBar: const AppNavBar(),
    body: Center(
      child: InkWell(
        onTap: locate,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 96),
            Text(state),
          ],
        ),
      ),
    ),
  );
}

class LensHero extends StatelessWidget {
  const LensHero({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Image.asset('assets/camera_lens.png', fit: BoxFit.contain),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    body: SafeArea(
      child: InkWell(
        onLongPress: () => showBuildInfo(context),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CapturePage()),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Image.asset(
              'assets/file_000000008284822fab87455a1155f93a.png',
              width: MediaQuery.sizeOf(context).width * .94,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    ),
  );
}

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(),
    body: SafeArea(
      child: Center(
        child: InkWell(
          onTap: () => takePhoto(context),
          child: LensHero(size: MediaQuery.sizeOf(context).width * .86),
        ),
      ),
    ),
  );
}

class PhotoReviewPage extends StatefulWidget {
  const PhotoReviewPage({
    super.key,
    required this.photo,
    required this.capturedAt,
    this.position,
  });
  final XFile photo;
  final DateTime capturedAt;
  final Position? position;
  @override
  State<PhotoReviewPage> createState() => _PhotoReviewPageState();
}

class _PhotoReviewPageState extends State<PhotoReviewPage> {
  late XFile photo;
  late DateTime capturedAt;
  Position? position;
  bool busy = false;
  bool saved = false;
  @override
  void initState() {
    super.initState();
    photo = widget.photo;
    capturedAt = widget.capturedAt;
    position = widget.position;
  }

  Future<void> retake() async {
    if (saved) return;
    final newer = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (newer != null && mounted) {
      final when = DateTime.now();
      final where = await capturePosition();
      if (mounted)
        setState(() {
          photo = newer;
          capturedAt = when;
          position = where;
        });
    }
  }

  Future<void> accept() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!saved) {
        await savePendingPhoto(photo, capturedAt, position);
        saved = true;
      }
      if (!mounted || !await ensureAuth(context) || !mounted) return;
      try {
        await uploadPendingPhotos();
      } catch (_) {
        if (mounted)
          toast(
            context,
            tr(
              context,
              'Снимок сохранён на телефоне. Отправим при подключении.',
            ),
          );
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const FeedPage()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted)
        toast(
          context,
          tr(
            context,
            saved
                ? 'Снимок сохранён на телефоне. Отправим при подключении.'
                : 'Не удалось сохранить фотографию. Повторите попытку.',
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget decisionButton(String letter, Color color, VoidCallback? onPressed) =>
      Semantics(
        label: tr(context, letter == 'N' ? 'Переснять' : 'Принять фотографию'),
        button: true,
        child: SizedBox(
          width: 90,
          height: 90,
          child: Material(
            color: color,
            shape: const CircleBorder(),
            elevation: 6,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: Icon(
                  letter == 'N' ? Icons.close : Icons.check,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    bottomNavigationBar: const AppNavBar(),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.file(File(photo.path), fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                decisionButton(
                  'N',
                  brandRed,
                  busy || saved ? null : retake,
                ),
                decisionButton(
                  'Y',
                  acceptGreen,
                  busy ? null : accept,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

const demoObjects = <String>[
  '📱',
  '👓',
  '🔑',
  '👛',
  '👜',
  '⌚',
  '🎧',
  '💻',
  '📷',
  '🎒',
  '☂️',
  '🧥',
  '👟',
  '🧤',
  '📚',
  '💳',
  '🪪',
  '🧳',
  '🚲',
  '🧸',
  '💍',
  '🧣',
  '🎩',
  '🏀',
  '🔦',
  '🎮',
  '🖊️',
  '🍼',
  '🕶️',
  '🎼',
];

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  Future<List<Map<String, dynamic>>>? items;
  void queueUpdated() {
    if (mounted) refresh();
  }

  @override
  void dispose() {
    queueChanges.removeListener(queueUpdated);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (db.auth.currentSession != null) items = loadItems();
    queueChanges.addListener(queueUpdated);
  }

  Future<List<Map<String, dynamic>>> loadItems() => db
      .from('finds')
      .select('id,finder_id,image_path,created_at,status')
      .neq('status', 'returned')
      .order('created_at', ascending: false)
      .limit(100);
  Future<void> refresh() async {
    if (db.auth.currentSession == null) return;
    setState(() {
      items = loadItems();
    });
    try {
      await items;
    } catch (_) {}
  }

  Future<void> signInForRealFinds() async {
    if (!await ensureAuth(context) || !mounted) return;
    await refresh();
  }

  void showDemoInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(
        tr(
          context,
          'Это демонстрационный пример. Настоящие находки доступны после входа.',
        ),
      ),
      actions: [
        IconButton(
          tooltip: tr(context, 'Войти для просмотра реальных находок'),
          icon: const Icon(Icons.login),
          onPressed: () {
            Navigator.pop(context);
            signInForRealFinds();
          },
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  void showClaim(Map<String, dynamic> find) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DetailPage(id: find['id'] as String, claimOnOpen: true),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(),
    body: SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: items,
          builder: (context, snap) {
            final signedIn = db.auth.currentSession != null;
            final loading =
                signedIn && snap.connectionState == ConnectionState.waiting;
            final failed = signedIn && snap.hasError;
            final real = signedIn
                ? (snap.data ?? <Map<String, dynamic>>[])
                : <Map<String, dynamic>>[];
            // Real finds always come first; examples appear only when there
            // is nothing real to show yet.
            final showDemo = real.isEmpty && !loading && !failed;
            final demos = demoObjects.take(8).toList();
            final count = showDemo ? demos.length : real.length;
            final header = loading || failed;
            final footer = !signedIn;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: count + (header ? 1 : 0) + (footer ? 1 : 0),
              itemBuilder: (context, listIndex) {
                if (header && listIndex == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator()
                          : IconButton.filled(
                              onPressed: refresh,
                              tooltip: tr(
                                context,
                                'Не удалось загрузить находки. Повторить',
                              ),
                              icon: const Icon(Icons.refresh),
                            ),
                    ),
                  );
                }
                final index = listIndex - (header ? 1 : 0);
                if (index == count) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: IconButton.filled(
                        onPressed: signInForRealFinds,
                        tooltip: tr(
                          context,
                          'Войти для просмотра реальных находок',
                        ),
                        iconSize: 34,
                        padding: const EdgeInsets.all(16),
                        icon: const Icon(Icons.login),
                      ),
                    ),
                  );
                }
                if (showDemo) {
                  return FilmFrame(
                    emoji: demos[index],
                    date: DateTime.now().subtract(
                      Duration(hours: (index + 1) * 4),
                    ),
                    onTap: showDemoInfo,
                    onClaim: showDemoInfo,
                  );
                }
                final data = real[index];
                final own = data['finder_id'] == db.auth.currentUser?.id;
                return FilmFrame(
                  image: db.storage
                      .from('finds')
                      .getPublicUrl(data['image_path'] as String),
                  date: DateTime.tryParse(
                    data['created_at']?.toString() ?? '',
                  )?.toLocal(),
                  status: data['status'] as String?,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailPage(id: data['id'] as String),
                    ),
                  ),
                  onClaim: own ? null : () => showClaim(data),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

// Dark film stock the reel is printed on.
const filmDark = Color(0xff121418);

// Punched sprocket holes running down one edge of the film.
class _Sprockets extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hole = Paint()..color = paper;
    const holeW = 9.0, holeH = 13.0, period = 23.0;
    final x = (size.width - holeW) / 2;
    for (double y = 6; y + holeH < size.height; y += period) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, holeW, holeH),
          const Radius.circular(3),
        ),
        hole,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// One frame of a vertical film reel: perforated rails each side, a rounded
// photo in the gate, a single claim action. Frames sit flush so the
// perforations read as one continuous strip scrolling top to bottom.
class FilmFrame extends StatelessWidget {
  const FilmFrame({
    super.key,
    this.image,
    this.emoji,
    this.date,
    this.status,
    this.onTap,
    this.onClaim,
  });
  final String? image;
  final String? emoji;
  final DateTime? date;
  final String? status;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;

  Color get _dot => switch (status) {
    'returned' => const Color(0xff9aa6ad),
    'handed_over' => const Color(0xffd98a1f),
    _ => acceptGreen,
  };

  @override
  Widget build(BuildContext context) {
    final stamp = date == null
        ? ''
        : '$date'.substring(0, 16).replaceFirst(' ', '  ');
    final rail = SizedBox(
      width: 22,
      child: CustomPaint(painter: _Sprockets()),
    );
    return Semantics(
      label: emoji == null ? 'Находка $stamp' : 'DEMO $stamp',
      child: Container(
        color: filmDark,
        height: 332,
        child: Row(
          children: [
            rail,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Opacity(
                  // Examples are dimmed so they never look like real finds.
                  opacity: emoji == null ? 1 : .55,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Material(
                      color: mist,
                      child: InkWell(
                        onTap: onTap,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (image != null)
                              Image.network(
                                image!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.black38,
                                    size: 42,
                                  ),
                                ),
                              ),
                            if (emoji != null)
                              Center(
                                child: Text(
                                  emoji!,
                                  style: const TextStyle(fontSize: 104),
                                ),
                              ),
                            if (status != null)
                              Positioned(
                                left: 12,
                                top: 12,
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: _dot,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            if (onClaim != null)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  elevation: 3,
                                  child: IconButton(
                                    tooltip: tr(context, 'Это моя вещь'),
                                    onPressed: onClaim,
                                    icon: const Icon(Icons.front_hand),
                                    color: brandRed,
                                    iconSize: 28,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            rail,
          ],
        ),
      ),
    );
  }
}

String statusText(BuildContext context, Map<String, dynamic> f) =>
    switch (f['status']) {
      'handed_over' => "${tr(context, 'Передано')}: ${f['handed_to'] ?? ''}",
      'returned' => tr(context, 'Возвращено владельцу'),
      _ => tr(context, 'У нашедшего'),
    };

// Status is shown as an icon; only the organisation name is written out.
Widget statusBadge(Map<String, dynamic> f) {
  final status = f['status'];
  final icon = switch (status) {
    'handed_over' => Icons.account_balance_outlined,
    'returned' => Icons.check_circle_outline,
    _ => Icons.inventory_2_outlined,
  };
  final handedTo = status == 'handed_over' ? '${f['handed_to'] ?? ''}' : '';
  return Row(
    children: [
      Icon(icon, color: status == 'returned' ? acceptGreen : ink, size: 28),
      if (handedTo.isNotEmpty) ...[
        const SizedBox(width: 10),
        Flexible(child: Text(handedTo, style: const TextStyle(fontSize: 16))),
      ],
    ],
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with WidgetsBindingObserver {
  bool busy = false, finished = false;
  StreamSubscription<AuthState>? authSubscription;

  void finishIfSignedIn() {
    if (finished || !mounted || db.auth.currentSession == null) return;
    finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null && !route.isFirst)
          Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => finishIfSignedIn());
    authSubscription = db.auth.onAuthStateChange.listen(
      (state) {
        if (state.session != null) finishIfSignedIn();
      },
      onError: (Object error) {
        if (mounted)
          toast(context, tr(context, 'Не удалось войти. Повторите попытку.'));
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) finishIfSignedIn();
  }

  // Native Google account picker: no browser, no redirect. When the web
  // client ID is not part of the build, the previous browser flow is used.
  Future<void> google() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (googleWebClientId.isEmpty) {
        await db.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: authCallback,
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
      } else {
        final account = await GoogleSignIn(
          serverClientId: googleWebClientId,
        ).signIn();
        if (account == null) return; // The person closed the account picker.
        final tokens = await account.authentication;
        final idToken = tokens.idToken;
        if (idToken == null) throw StateError('Google did not return an ID token');
        await db.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: tokens.accessToken,
        );
      }
    } catch (e) {
      if (mounted)
        toast(context, tr(context, 'Не удалось войти. Повторите попытку.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apple() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: authCallback,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted)
        toast(context, tr(context, 'Не удалось войти. Повторите попытку.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(signingIn: true),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Google',
                  button: true,
                  enabled: !busy,
                  child: Tooltip(
                    message: 'Google',
                    child: SizedBox.square(
                      dimension: 96,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const Key('google-sign-in'),
                          customBorder: const CircleBorder(),
                          onTap: busy ? null : google,
                          child: Ink.image(
                            image: const AssetImage('assets/google_sign_in.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (Platform.isIOS) ...[
                  const SizedBox(height: 22),
                  IconButton.filled(
                    onPressed: busy ? null : apple,
                    icon: const Icon(Icons.apple, size: 46),
                    tooltip: 'Apple',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(92, 92),
                    ),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// Coordinates are never requested by the app: the server hides them.
const findColumns =
    'id,finder_id,image_path,description,place_label,status,handed_to,created_at';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.id, this.claimOnOpen = false});
  final String id;
  final bool claimOnOpen;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<Map<String, dynamic>> find;
  bool claimStarted = false;
  Future<Map<String, dynamic>> loadFind() =>
      db.from('finds').select(findColumns).eq('id', widget.id).single();
  void reload() {
    setState(() {
      find = loadFind();
    });
  }

  @override
  void initState() {
    super.initState();
    find = loadFind();
  }

  Future<void> claim(Map<String, dynamic> f) async {
    if (!await ensureAuth(context) || !mounted) return;
    if (f['finder_id'] == db.auth.currentUser!.id) {
      toast(context, tr(context, 'Это ваше объявление'));
      return;
    }
    final message = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: TextField(
          controller: message,
          maxLength: 500,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr(context, 'Напишите нашедшему сообщение'),
          ),
        ),
        actions: [
          IconButton(
            tooltip: tr(context, 'Отмена'),
            onPressed: () => Navigator.pop(c, false),
            icon: const Icon(Icons.close),
          ),
          IconButton.filled(
            tooltip: tr(context, 'Отправить'),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
    if (ok != true || message.text.trim().isEmpty || !mounted) {
      message.dispose();
      return;
    }
    try {
      await db.from('claims').insert({
        'find_id': widget.id,
        'claimant_id': db.auth.currentUser!.id,
        'message': message.text.trim(),
      });
      if (mounted) {
        toast(context, tr(context, 'Сообщение отправлено'));
        setState(() {});
      }
    } catch (e) {
      if (mounted)
        toast(context, tr(context, 'Не удалось отправить сообщение.'));
    }
    message.dispose();
  }

  Future<void> updateStatus(String status) async {
    final org = TextEditingController();
    if (status == 'handed_over') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: TextField(
            controller: org,
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr(context, 'Полиция, бюро находок…'),
            ),
          ),
          actions: [
            IconButton(
              tooltip: tr(context, 'Отмена'),
              onPressed: () => Navigator.pop(c, false),
              icon: const Icon(Icons.close),
            ),
            IconButton.filled(
              tooltip: tr(context, 'Сохранить'),
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.check),
            ),
          ],
        ),
      );
      if (ok != true || org.text.trim().isEmpty) {
        org.dispose();
        return;
      }
    }
    try {
      await db
          .from('finds')
          .update({
            'status': status,
            'handed_to': status == 'handed_over' ? org.text.trim() : null,
          })
          .eq('id', widget.id);
      reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    org.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(),
    body: FutureBuilder<Map<String, dynamic>>(
      future: find,
      builder: (c, s) {
        if (s.hasError) {
          return Center(
            child: IconButton.filled(
              onPressed: reload,
              tooltip: tr(context, 'Не удалось загрузить находки. Повторить'),
              icon: const Icon(Icons.refresh),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final f = s.data!, own = db.auth.currentUser?.id == f['finder_id'];
        if (widget.claimOnOpen &&
            !claimStarted &&
            !own &&
            f['status'] != 'returned') {
          claimStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) claim(f);
          });
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 360,
                color: mist,
                child: Image.network(
                  db.storage
                      .from('finds')
                      .getPublicUrl(f['image_path'] as String),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 42),
                  ),
                ),
              ),
            ),
            if (f['description'] != 'Фото') ...[
              const SizedBox(height: 14),
              Text(
                f['description'],
                style: Theme.of(c).textTheme.headlineSmall,
              ),
            ],
            const SizedBox(height: 16),
            statusBadge(f),
            if (f['place_label'] != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 28),
                  const SizedBox(width: 10),
                  Flexible(child: Text('${f['place_label']}')),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!own && f['status'] != 'returned')
                  IconButton.filled(
                    tooltip: tr(context, 'Это моя вещь'),
                    onPressed: () => claim(f),
                    iconSize: 34,
                    padding: const EdgeInsets.all(16),
                    icon: const Icon(Icons.pan_tool_alt_outlined),
                  ),
                if (own) ...[
                  IconButton.outlined(
                    tooltip: tr(context, 'Передано организации'),
                    onPressed: () => updateStatus('handed_over'),
                    iconSize: 32,
                    padding: const EdgeInsets.all(14),
                    icon: const Icon(Icons.account_balance_outlined),
                  ),
                  const SizedBox(width: 20),
                  IconButton.outlined(
                    tooltip: tr(context, 'Возвращено владельцу'),
                    onPressed: () => updateStatus('returned'),
                    iconSize: 32,
                    padding: const EdgeInsets.all(14),
                    icon: const Icon(Icons.done_all),
                  ),
                ],
              ],
            ),
            const Divider(height: 36),
            if (db.auth.currentUser == null)
              Center(
                child: IconButton.outlined(
                  tooltip: tr(context, 'Войти через Google'),
                  onPressed: () => ensureAuth(context).then((_) {
                    if (mounted) setState(() {});
                  }),
                  icon: const Icon(Icons.login),
                ),
              ),
            if (db.auth.currentUser != null)
              ClaimsView(findId: widget.id, finderId: f['finder_id'] as String),
          ],
        );
      },
    ),
  );
}

class ClaimsView extends StatefulWidget {
  const ClaimsView({super.key, required this.findId, required this.finderId});
  final String findId, finderId;
  @override
  State<ClaimsView> createState() => _ClaimsViewState();
}

class _ClaimsViewState extends State<ClaimsView> {
  late Future<List<Map<String, dynamic>>> claims;
  Future<List<Map<String, dynamic>>> loadClaims() => db
      .from('claims')
      .select()
      .eq('find_id', widget.findId)
      .order('created_at');
  void reload() {
    setState(() {
      claims = loadClaims();
    });
  }

  @override
  void initState() {
    super.initState();
    claims = loadClaims();
  }

  Future<void> reply(String id) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: TextField(
          controller: t,
          maxLength: 500,
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          IconButton(
            tooltip: tr(context, 'Отмена'),
            onPressed: () => Navigator.pop(c, false),
            icon: const Icon(Icons.close),
          ),
          IconButton.filled(
            tooltip: tr(context, 'Ответить'),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) {
      try {
        await db
            .from('claims')
            .update({'response': t.text.trim()})
            .eq('id', id);
        reload();
      } catch (e) {
        if (mounted) toast(context, '$e');
      }
    }
    t.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: claims,
    builder: (c, s) {
      if (s.hasError) {
        return Center(
          child: IconButton(
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
        );
      }
      if (!s.hasData) return const LinearProgressIndicator();
      if (s.data!.isEmpty) return const SizedBox.shrink();
      return Column(
        children: [
          for (final claim in s.data!)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${claim['message']}'),
                  if (claim['response'] != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.reply, size: 22, color: brandRed),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${claim['response']}')),
                      ],
                    ),
                  ],
                  if (db.auth.currentUser?.id == widget.finderId &&
                      claim['response'] == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: tr(context, 'Ответить'),
                        onPressed: () => reply(claim['id'] as String),
                        icon: const Icon(Icons.reply),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<AuthState>? authSubscription;
  @override
  void initState() {
    super.initState();
    authSubscription = db.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  Future<void> signOut() async {
    try {
      await db.auth.signOut();
      if (googleWebClientId.isNotEmpty) {
        // Forget the Google account so the picker appears again next time.
        await GoogleSignIn(serverClientId: googleWebClientId).signOut();
      }
    } catch (_) {
      /* The local session is cleared even when the network is unavailable. */
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = db.auth.currentUser;
    final email = user?.email;
    return Scaffold(
      appBar: const ZambaruBar(),
      bottomNavigationBar: const AppNavBar(),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: mist,
              child: Icon(Icons.person_outline, size: 48, color: ink),
            ),
          ),
          const SizedBox(height: 16),
          if (email != null)
            Center(child: Text(email, style: const TextStyle(fontSize: 16))),
          const SizedBox(height: 28),
          Center(
            child: user == null
                ? IconButton.filled(
                    tooltip: tr(context, 'Войти через Google'),
                    onPressed: () =>
                        ensureAuth(context).then((_) {
                          if (mounted) setState(() {});
                        }),
                    iconSize: 34,
                    padding: const EdgeInsets.all(16),
                    icon: const Icon(Icons.login),
                  )
                : IconButton.outlined(
                    tooltip: tr(context, 'Выйти'),
                    onPressed: signOut,
                    iconSize: 30,
                    padding: const EdgeInsets.all(14),
                    icon: const Icon(Icons.logout),
                  ),
          ),
        ],
      ),
    );
  }
}

const posters = <String, List<String>>{
  'EN': ['LOST SOMETHING?', ''],
  'RU': ['ПОТЕРЯЛАСЬ ВЕЩЬ?', ''],
  'TR': ['BİR EŞYA MI KAYBETTİNİZ?', ''],
  'ZH': ['丢东西了吗？', ''],
  'UR': ['کوئی چیز کھو گئی؟', ''],
  'ID': ['KEHILANGAN BARANG?', ''],
  'IT': ['HAI PERSO QUALCOSA?', ''],
  'FR': ['VOUS AVEZ PERDU UN OBJET ?', ''],
  'ES': ['¿PERDISTE ALGO?', ''],
  'AR': ['هل فقدت شيئًا؟', ''],
  'JA': ['物を失くしましたか？', ''],
  'KO': ['물건을 잃어버리셨나요?', ''],
  'PT': ['PERDEU ALGUMA COISA?', ''],
  'HI': ['कोई चीज़ खो गई?', ''],
  'BN': ['কিছু হারিয়েছেন?', ''],
  'AZ': ['ƏŞYANIZ İTİB?', ''],
};
// Title, placement instructions, QR placeholder, missing link, print error.
const posterUi = <String, List<String>>{
  'EN': [
    'Poster',
    'Print and post in busy places where permitted.',
    'The QR code will appear once the link is set up.',
    'Set up the permanent LOST link to enable the QR code.',
    'Printing error',
  ],
  'RU': [
    'Плакат',
    'Распечатай и приклей в людных местах, где это разрешено.',
    'QR-код появится после настройки ссылки.',
    'Сначала задайте постоянную ссылку LOST.',
    'Ошибка печати',
  ],
  'TR': [
    'Afiş',
    'Yazdırın ve izin verilen kalabalık yerlere asın.',
    'Bağlantı ayarlandıktan sonra QR kodu görünecek.',
    'Önce kalıcı LOST bağlantısını ayarlayın.',
    'Yazdırma hatası',
  ],
  'ZH': [
    '海报',
    '请打印并张贴在人流密集且允许张贴的地方。',
    '设置链接后将显示二维码。',
    '请先设置 LOST 的永久链接。',
    '打印错误',
  ],
  'UR': [
    'پوسٹر',
    'پرنٹ کریں اور لوگوں کی بھیڑ والی جگہوں پر لگائیں، جہاں اجازت ہو۔',
    'لنک سیٹ ہونے کے بعد کیو آر کوڈ ظاہر ہوگا۔',
    'پہلے LOST کا مستقل لنک سیٹ کریں۔',
    'پرنٹنگ میں خرابی',
  ],
  'ID': [
    'Poster',
    'Cetak dan tempel di tempat ramai yang mengizinkannya.',
    'Kode QR akan muncul setelah tautan diatur.',
    'Atur tautan permanen LOST terlebih dahulu.',
    'Gagal mencetak',
  ],
  'IT': [
    'Locandina',
    'Stampa e affiggi in luoghi affollati dove è consentito.',
    'Il codice QR apparirà dopo aver impostato il link.',
    'Imposta prima il link permanente di LOST.',
    'Errore di stampa',
  ],
  'FR': [
    'Affiche',
    'Imprimez et affichez dans les lieux fréquentés où cela est autorisé.',
    'Le code QR apparaîtra une fois le lien configuré.',
    'Configurez d’abord le lien permanent de LOST.',
    'Erreur d’impression',
  ],
  'ES': [
    'Cartel',
    'Imprime y pega en lugares concurridos donde esté permitido.',
    'El código QR aparecerá cuando se configure el enlace.',
    'Configure primero el enlace permanente de LOST.',
    'Error de impresión',
  ],
  'AR': [
    'ملصق',
    'اطبع وعلّق في الأماكن المزدحمة حيث يُسمح بذلك.',
    'سيظهر رمز QR بعد إعداد الرابط.',
    'اضبط رابط LOST الدائم أولاً.',
    'خطأ في الطباعة',
  ],
  'JA': [
    'ポスター',
    '印刷し、掲示が許可されている人の多い場所に貼ってください。',
    'リンクの設定後にQRコードが表示されます。',
    '最初にLOSTの固定リンクを設定してください。',
    '印刷エラー',
  ],
  'KO': [
    '포스터',
    '인쇄하여 게시가 허용된 사람이 많은 곳에 붙이세요.',
    '링크를 설정하면 QR 코드가 표시됩니다.',
    'LOST의 고정 링크를 먼저 설정하세요.',
    '인쇄 오류',
  ],
  'PT': [
    'Cartaz',
    'Imprima e afixe em locais movimentados onde for permitido.',
    'O código QR aparecerá após a configuração do link.',
    'Configure primeiro o link permanente do LOST.',
    'Erro de impressão',
  ],
  'HI': [
    'पोस्टर',
    'प्रिंट करें और भीड़ वाली जगहों पर लगाएँ, जहाँ इसकी अनुमति हो।',
    'लिंक सेट होने के बाद QR कोड दिखाई देगा।',
    'पहले LOST का स्थायी लिंक सेट करें।',
    'प्रिंट करने में त्रुटि',
  ],
  'BN': [
    'পোস্টার',
    'প্রিন্ট করে জনসমাগমের স্থানে লাগান, যেখানে অনুমতি আছে।',
    'লিংক সেট করার পর QR কোড দেখা যাবে।',
    'আগে LOST-এর স্থায়ী লিংক সেট করুন।',
    'প্রিন্ট করতে সমস্যা হয়েছে',
  ],
  'AZ': [
    'Plakat',
    'Çap et və icazə verilən insanların çox olduğu yerlərə yapışdır.',
    'Keçid qurulandan sonra QR kod görünəcək.',
    'Əvvəlcə LOST-un daimi keçidini qurun.',
    'Çap xətası',
  ],
};
const navLabels = <String, List<String>>{
  'EN': ['Profile', 'Languages', 'Location', 'Feed'],
  'RU': ['Профиль', 'Языки', 'Место', 'Лента'],
  'TR': ['Profil', 'Diller', 'Konum', 'Akış'],
  'ZH': ['个人资料', '语言', '位置', '动态'],
  'UR': ['پروفائل', 'زبانیں', 'مقام', 'فیڈ'],
  'ID': ['Profil', 'Bahasa', 'Lokasi', 'Kabar'],
  'IT': ['Profilo', 'Lingue', 'Posizione', 'Bacheca'],
  'FR': ['Profil', 'Langues', 'Lieu', 'Fil'],
  'ES': ['Perfil', 'Idiomas', 'Ubicación', 'Noticias'],
  'AR': ['الملف الشخصي', 'اللغات', 'الموقع', 'المنشورات'],
  'JA': ['プロフィール', '言語', '場所', 'フィード'],
  'KO': ['프로필', '언어', '위치', '피드'],
  'PT': ['Perfil', 'Idiomas', 'Localização', 'Feed'],
  'HI': ['प्रोफ़ाइल', 'भाषाएँ', 'स्थान', 'फ़ीड'],
  'BN': ['প্রোফাইল', 'ভাষা', 'অবস্থান', 'ফিড'],
  'AZ': ['Profil', 'Dillər', 'Məkan', 'Lent'],
};

class LanguagesPage extends StatelessWidget {
  const LanguagesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    bottomNavigationBar: const AppNavBar(),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              padding: const EdgeInsets.all(18),
              children: [
                for (final entry in interfaceLanguages.entries)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        backgroundColor:
                            appLanguage.value.languageCode == entry.key
                            ? acceptGreen
                            : null,
                      ),
                      onPressed: () async {
                        try {
                          await setAppLanguage(entry.key);
                        } catch (_) {
                          if (context.mounted)
                            toast(
                              context,
                              tr(context, 'Не удалось сохранить язык.'),
                            );
                        }
                      },
                      child: Text(entry.value),
                    ),
                  ),
              ],
            ),
          ),
          IconButton.filled(
            icon: const Icon(Icons.print),
            tooltip: tr(context, 'Язык плаката'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PosterLanguagesPage()),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class PosterLanguagesPage extends StatelessWidget {
  const PosterLanguagesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ZambaruBar(),
    bottomNavigationBar: const AppNavBar(),
    body: GridView.count(
      crossAxisCount: 4,
      childAspectRatio: 1.3,
      padding: const EdgeInsets.all(18),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final code in posters.keys)
          Material(
            color: mist,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PosterPage(code: code)),
              ),
              child: Center(
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class PosterPage extends StatefulWidget {
  const PosterPage({super.key, required this.code});
  final String code;
  @override
  State<PosterPage> createState() => _PosterPageState();
}

class _PosterPageState extends State<PosterPage> {
  final boundary = GlobalKey();
  bool get rightToLeft => const {'AR', 'UR'}.contains(widget.code);

  Future<void> printPoster() async {
    try {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 420x594 logical pixels at 5x gives about 250 dpi on A4.
      final image = await render.toImage(pixelRatio: 5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final doc = pw.Document();
      final picture = pw.MemoryImage(bytes!.buffer.asUint8List());
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) =>
              pw.Center(child: pw.Image(picture, fit: pw.BoxFit.contain)),
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'LOST-${widget.code}',
      );
    } catch (e) {
      if (mounted) toast(context, '${posterUi[widget.code]![4]}: $e');
    }
  }

  // A4 proportions. Emblem, brand name, one sentence, QR code.
  Widget buildPoster(String headline) => Container(
    width: 420,
    height: 594,
    color: Colors.white,
    padding: const EdgeInsets.all(18),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: brandRed, width: 6),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            'assets/file_000000008284822fab87455a1155f93a.png',
            width: 110,
            height: 110,
          ),
          const Text(
            'LOST',
            style: TextStyle(
              color: brandRed,
              fontSize: 46,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          SizedBox(
            height: 92,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Directionality(
                  textDirection: rightToLeft
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (appLink.isNotEmpty)
            QrImageView(
              data: appLink,
              size: 210,
              backgroundColor: Colors.white,
            ),
          if (appLink.isEmpty)
            Container(
              width: 210,
              height: 210,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: const Icon(Icons.qr_code_2, size: 96, color: Colors.grey),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = posters[widget.code]!;
    return Scaffold(
      appBar: const ZambaruBar(),
      bottomNavigationBar: AppNavBar(language: widget.code),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 18),
                        ],
                      ),
                      child: RepaintBoundary(
                        key: boundary,
                        child: buildPoster(text[0]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IconButton.filled(
                onPressed: printPoster,
                tooltip: posterUi[widget.code]![0],
                iconSize: 32,
                padding: const EdgeInsets.all(16),
                icon: const Icon(Icons.print),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
