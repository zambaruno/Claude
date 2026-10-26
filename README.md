# LOST — первая рабочая версия

Flutter-приложение для Android. Стартовый экран показывает только красную эмблему без нижней панели. Нажатие открывает второй экран с большим объективом. Внутренняя панель содержит только значки камеры, языка, поддержки и киноленты. Маленький объектив использует тот же сценарий съёмки, что и большой. Страница Profile сохранена в коде.

После снимка красная N открывает камеру повторно, зелёная Y сохраняет находку на телефоне. При отсутствии сессии доступны Google и Apple на iOS. Сессия сохраняется SDK. Повторное Y не создаёт второй локальный экземпляр принятого снимка.

Принятые фотографии и скрытые геометки сохраняются в локальной очереди. Отправка повторяется при запуске, входе, возвращении в приложение и каждые 30 секунд, пока приложение открыто. Это не фоновая служба: после закрытия LOST очередь ждёт следующего запуска. Стабильный UUID позволяет восстановиться после потерянного ответа сервера без повторного объявления. Очередь привязывается к аккаунту перед первой отправкой; снимки другого аккаунта не отправляются. При недоступной геолокации координаты могут отсутствовать. Координаты не отображаются в ленте; доступ к ним через серверный API требует отдельной проверки политик.

Значок принтера открывает 16 языков плаката. На плакате только LOST, вопрос о потерянной вещи и QR-код при наличии постоянной ссылки; инструкция о разрешённом размещении остаётся за пределами печати. Выбор языка интерфейса не вынесен в навигацию по более позднему решению пользователя.

Кнопки поддержки содержат только числа: 1, 2, 3, 5, 10, 20, 50, 100, 500, 1000, 2000, 5000, 10000. Единица расчёта — USD. Выбор суммы передаётся выбранному способу оплаты; настоящая оплата пока не подключена.

## Проверка и тестовая сборка

Перед сборкой выполняйте `flutter analyze lib test --no-fatal-infos --no-fatal-warnings`, затем `flutter test`. Тесты проверяют сохранение офлайн-очереди, восстановление после потерянного ответа сервера без дублирования, сохранение языка, кнопки сумм и отсутствие email-входа.

Существующий `.github/workflows/android.yml` выполняет анализ и тесты после изменений main; debug APK собирается при ручном запуске после накопления примерно 5–6 исправлений; артефакт называется `LOST-build-<номер>-arm64-debug-APK`. После накопления примерно 5–6 исправлений установите APK на телефон и проверьте камеру, N/Y, вход через Google, сохранение сессии после перезапуска и офлайн-синхронизацию. GitHub-тесты не подтверждают настоящий OAuth-вход или работу камеры на устройстве.

Публикация в Google Play и изменения production выполняются только по отдельному решению. Обычные изменения приложения не меняют `.github/play-release-trigger.txt` и не запускают отправку AAB.

## Подготовка

1. Используйте существующий проект `zambaruno-lost` в организации `zambaruno`.
2. Для проекта `zambaruno-lost` таблицы и политики уже применены. Если создаёте другой пустой проект, выполните `supabase/schema.sql`, затем `supabase/security_hardening.sql` (если включена автоматическая RLS).
3. В Authentication → Sign In / Providers проверьте настройки Google (и Apple для iOS). В Authentication → URL Configuration сохраните разрешённый Redirect URL `com.zambaruno.lost://login-callback/`: он используется для возврата из социального входа. Вход по письму удалён из приложения. SDK Supabase сохраняет сессию между запусками.
4. В Project Settings / API возьмите Project URL и **publishable / anon** key. Никогда не используйте service_role / secret key в мобильном приложении.
5. Установите Flutter SDK и Android Studio. В этой папке выполните `flutter create --platforms android --org com.zambaruno --project-name lost .`, затем `flutter pub get`.
6. После `flutter create` откройте `android/app/src/main/AndroidManifest.xml`. Добавьте `android.permission.ACCESS_FINE_LOCATION` и `android.permission.INTERNET`, если их нет. Внутри `<activity ...>` (до `</activity>`) отключите стандартный обработчик deep links Flutter и добавьте обработчик ссылки Supabase:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.zambaruno.lost" android:host="login-callback" />
</intent-filter>
```

   Проверьте, что minSdk соответствует требованиям зависимостей. После входа Google браузер возвращает пользователя в установленное приложение LOST.
7. Запустите:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

После появления постоянного адреса сайта LOST укажите также `--dart-define=LOST_APP_LINK=https://your-domain.example/lost`. До этого печать QR намеренно выключена. Ссылка должна принадлежать вам и вести к приложению, а не к чужому одноимённому продукту.

Bucket `finds` ограничен на сервере файлами JPEG размером до 2 МБ; приложение дополнительно уменьшает снимок до 1600 px, сжимает и проверяет размер до загрузки. Если вход прервётся, принятый снимок остаётся в папке приложения на телефоне до успешной отправки. Удаление приложения удалит и этот ещё не отправленный снимок.

## Ограничения первой версии

- Проверка `flutter analyze` и сборка debug APK проходят в GitHub Actions. Вход через Google и открытие камеры требуют проверки на реальном телефоне.
- Сообщения заявителя и ответ нашедшего доступны только этим двум сторонам. Это пока один вопрос и один ответ, а не полноценный чат.
- Карточки находок публичные. Не размещайте на фото документы, номера карт и другую чувствительную информацию.
- Плакат содержит 16 предварительных переводов; носители языков должны проверить формулировки до массовой печати.

## Google Play: draft internal release

The manual workflow `.github/workflows/play_aab.yml` builds a signed AAB. Each run uses a new Android versionCode derived from the GitHub run number and attempt. It uploads an artifact named `LOST-Play-release-AAB`.

Four repository secrets provide the existing Play upload signing key:

- `LOST_UPLOAD_KEYSTORE_BASE64`: one-line Base64 of the upload keystore (.jks).
- `LOST_UPLOAD_STORE_PASSWORD`: keystore password.
- `LOST_UPLOAD_KEY_ALIAS`: key alias.
- `LOST_UPLOAD_KEY_PASSWORD`: key password.

The `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` repository secret contains the entire JSON credential for the `lost-play-publisher` service account. The service account must have access to app `com.zambaruno.lost` in Play Console. Keep the JSON out of the repository, screenshots, chat, and build logs.

In GitHub Actions → Build Play release AAB → Run workflow, `upload_to_play` defaults to true. The workflow creates a **draft on the internal testing track**, It does not activate a release for testers or publish to production. Set `upload_to_play` to false to build only. After a successful run, inspect the draft in Play Console, complete required app declarations, and deliberately roll it out to start testing.



## Версия 0.1.1

Google показан официальной цветной кнопкой из набора https://developers.google.com/static/identity/images/signin-assets.zip (Android + Web, Light, icon-only pill, @4x). Исходное изображение не изменено. Демо-карточки доступны без входа; нажатие объясняет, что это пример. Ошибка загрузки реальных находок показывает кнопку повтора, загрузка — индикатор.

Долгое нажатие на стартовую эмблему открывает номер сборки и короткий SHA. Workflow задаёт Android versionCode из номера запуска; commit с `[build apk]` запускает сборку после анализа и тестов. APK собирается только для arm64 (Galaxy S23 и другие современные Android). Срок хранения артефакта — один день. Сборка и скачивание не публикуют приложение в Play.


Платёжный переход подготовлен для Zambaruno LLC. Публичная переменная GitHub Actions `LOST_PAYPAL_ME` должна содержать подтверждённую ссылку получателя вида `https://paypal.me/<получатель>`. Выбранная сумма передаётся в USD. Для карты/Google Pay/Apple Pay переменная `LOST_CHECKOUT_LINKS` содержит JSON со ссылками Stripe Payment Links по каждой сумме (`{"1":"https://buy.stripe.com/..."}`). Ссылки создаются в аккаунте получателя с соответствующими суммой и валютой; кошельки показывает провайдер при поддержке устройством. Закрытые ключи не нужны в APK. Без ссылок приложение честно сообщает об отсутствии подключения и не открывает посторонний кошелёк. Публичные ссылки получателя пока не предоставлены, поэтому реальные платежи не активированы. Открытие браузера не считается успешной оплатой.


## Версия 0.2.0

**Вход через Google без браузера.** Кнопка Google открывает системный выбор аккаунта Gmail на телефоне (пакет `google_sign_in` и `signInWithIdToken`). Если в сборку не передан `GOOGLE_WEB_CLIENT_ID`, приложение возвращается к прежнему входу через браузер, поэтому ничего не ломается до настройки.

Настройка один раз:

1. Google Cloud → APIs & Services → Credentials. Web client ID уже есть: он указан в Supabase → Authentication → Providers → Google. Сохраните его как переменную GitHub Actions `GOOGLE_WEB_CLIENT_ID` (Settings → Secrets and variables → Actions → Variables). Это публичный идентификатор, не секрет.
2. Создайте там же OAuth client типа **Android**: package `com.zambaruno.lost` и SHA-1. Для тестовых APK SHA-1 печатает шаг «Print debug signing SHA-1» в логе workflow. Для Google Play нужен SHA-1 из Play Console → Setup → App signing (и upload key).
3. В Supabase в провайдере Google проверьте, что указан тот же Web client ID. Если вход сообщает о nonce, включите там «Skip nonce checks».

**Координаты больше не читаются клиентами.** До этой версии любой человек, даже без входа, мог получить точные широту и долготу каждой находки через публичный API. Выполните `supabase/coordinates_hardening.sql` один раз, **после** того как у тестировщиков установлена версия 0.2.0 (старые версии читали эти поля и перестанут открывать карточку находки).

**Внешний вид.** Светлая плоская тема под красную эмблему, значки вместо надписей, одна лента без плёнки и рекламной заглушки. Настоящие находки показываются первыми, примеры только когда настоящих нет. Страница профиля (вход и выход) теперь доступна из нижней панели; раньше выйти из аккаунта было нельзя.

**Плакат.** Постоянная ссылка по умолчанию ведёт на страницу приложения в Google Play (`https://play.google.com/store/apps/details?id=com.zambaruno.lost`), поэтому QR-код теперь есть всегда. Чтобы заменить, передайте `LOST_APP_LINK`. Плакат рисуется в формате A4 с разрешением около 250 dpi, для арабского и урду текст идёт справа налево.
