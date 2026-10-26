import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

const interfaceLanguages = {
  'ru': 'RU',
  'en': 'EN',
  'az': 'AZ',
  'tr': 'TR',
  'es': 'ES',
};
final appLanguage = ValueNotifier<Locale>(const Locale('ru'));
Future<File> _languageFile() async =>
    File('${(await getApplicationDocumentsDirectory()).path}/language.json');
Future<void> loadAppLanguage() async {
  final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  var code = interfaceLanguages.containsKey(system) ? system : 'en';
  try {
    final file = await _languageFile();
    if (await file.exists()) {
      final saved = jsonDecode(await file.readAsString());
      if (saved is String && interfaceLanguages.containsKey(saved))
        code = saved;
    }
  } catch (_) {
    /* A damaged preference must not prevent opening LOST. */
  }
  appLanguage.value = Locale(code);
}

Future<void> setAppLanguage(String code) async {
  if (!interfaceLanguages.containsKey(code)) return;
  final file = await _languageFile();
  final staged = File('${file.path}.tmp');
  await staged.writeAsString(jsonEncode(code), flush: true);
  await staged.rename(file.path);
  appLanguage.value = Locale(code);
}

String tr(BuildContext context, String russian) =>
    translations[Localizations.localeOf(context).languageCode]?[russian] ??
    russian;

const translations = <String, Map<String, String>>{
  "en": {
    "Приём платежей Zambaruno LLC ещё не подключён.": "Payments to Zambaruno LLC are not connected yet.",
    "Не удалось открыть оплату. Повторите попытку.": "Could not open checkout. Try again.",

    "Не удалось загрузить находки. Повторить": "Could not load finds. Retry",
    "Это демонстрационный пример. Настоящие находки доступны после входа.": "This is a demo example. Sign in to view real finds.",

    "Камера": "Camera",
    "Языки": "Languages",
    "Поддержать": "Support",
    "Лента": "Feed",
    "Переснять": "Retake",
    "Принять фотографию": "Accept photo",
    "Язык плаката": "Poster language",
    "Оплата пока не подключена.": "Payments are not connected yet.",
    "Проверьте электронный адрес.": "Check your email address.",
    "Подождите минуту перед повторной отправкой.":
        "Wait a minute before sending again.",
    "Не удалось отправить ссылку. Повторите попытку.":
        "Could not send the link. Try again.",
    "Отправить ссылку": "Send link",
    "Откройте ссылку из письма на этом телефоне.":
        "Open the email link on this phone.",
    "Снимок сохранён на телефоне. Отправим при подключении.":
        "Photo saved on this phone. It will upload when connected.",
    "Не удалось сохранить фотографию. Повторите попытку.":
        "Could not save the photo. Try again.",
    "Не удалось сохранить язык.": "Could not save the language.",
    "Войти для просмотра реальных находок": "Sign in to view real finds",
    "Это моя вещь": "This is mine",
    "Возвращено владельцу": "Returned to owner",
    "У нашедшего": "Held by finder",
    "Передано": "Handed over",
    "Это ваше объявление": "This is your listing",
    "Напишите нашедшему сообщение": "Write a message to the finder",
    "Отмена": "Cancel",
    "Отправить": "Send",
    "Сообщение отправлено": "Message sent",
    "Куда передана вещь?": "Where was the item handed over?",
    "Полиция, бюро находок…": "Police, lost property office…",
    "Сохранить": "Save",
    "Находка": "Find",
    "Место находки": "Find location",
    "Передано организации": "Handed over to an organization",
    "Сообщения по этой вещи": "Messages about this item",
    "Для сообщений войдите по email.": "Sign in to send messages.",
    "Ответить": "Reply",
    "Пока сообщений нет.": "No messages yet.",
    "Ответ нашедшего": "Finder response",
    "Профиль": "Profile",
    "Без регистрации": "Not signed in",
    "Войти через Google": "Sign in",
    "Выйти": "Sign out",
    "Не удалось войти. Повторите попытку.": "Could not sign in. Try again.",
    "Не удалось отправить сообщение.": "Could not send the message.",
  },
  "az": {
    "Приём платежей Zambaruno LLC ещё не подключён.": "Zambaruno LLC üçün ödəniş qəbulu hələ qoşulmayıb.",
    "Не удалось открыть оплату. Повторите попытку.": "Ödənişi açmaq mümkün olmadı. Yenidən cəhd edin.",

    "Не удалось загрузить находки. Повторить": "Tapıntılar yüklənmədi. Yenidən cəhd edin",
    "Это демонстрационный пример. Настоящие находки доступны после входа.": "Bu, nümayiş nümunəsidir. Həqiqi tapıntıları görmək üçün daxil olun.",

    "Камера": "Kamera",
    "Языки": "Dillər",
    "Поддержать": "Dəstək",
    "Лента": "Lent",
    "Переснять": "Yenidən çək",
    "Принять фотографию": "Şəkli qəbul et",
    "Язык плаката": "Plakatın dili",
    "Оплата пока не подключена.": "Ödəniş hələ qoşulmayıb.",
    "Проверьте электронный адрес.": "E-poçt ünvanını yoxlayın.",
    "Подождите минуту перед повторной отправкой.":
        "Yenidən göndərməzdən əvvəl bir dəqiqə gözləyin.",
    "Не удалось отправить ссылку. Повторите попытку.":
        "Keçid göndərilmədi. Yenidən cəhd edin.",
    "Отправить ссылку": "Keçid göndər",
    "Откройте ссылку из письма на этом телефоне.":
        "Məktubdakı keçidi bu telefonda açın.",
    "Снимок сохранён на телефоне. Отправим при подключении.":
        "Şəkil telefonda saxlanıldı. Bağlantı olduqda göndəriləcək.",
    "Не удалось сохранить фотографию. Повторите попытку.":
        "Şəkil saxlanılmadı. Yenidən cəhd edin.",
    "Не удалось сохранить язык.": "Dil saxlanılmadı.",
    "Войти для просмотра реальных находок":
        "Real tapıntıları görmək üçün daxil olun",
    "Это моя вещь": "Bu mənim əşyamdır",
    "Возвращено владельцу": "Sahibinə qaytarılıb",
    "У нашедшего": "Tapan şəxsdədir",
    "Передано": "Təhvil verilib",
    "Это ваше объявление": "Bu sizin elanınızdır",
    "Напишите нашедшему сообщение": "Tapan şəxsə mesaj yazın",
    "Отмена": "Ləğv et",
    "Отправить": "Göndər",
    "Сообщение отправлено": "Mesaj göndərildi",
    "Куда передана вещь?": "Əşya hara təhvil verilib?",
    "Полиция, бюро находок…": "Polis, tapıntılar bürosu…",
    "Сохранить": "Saxla",
    "Находка": "Tapıntı",
    "Место находки": "Tapıldığı yer",
    "Передано организации": "Təşkilata təhvil verilib",
    "Сообщения по этой вещи": "Bu əşya haqqında mesajlar",
    "Для сообщений войдите по email.": "Mesaj yazmaq üçün daxil olun.",
    "Ответить": "Cavab ver",
    "Пока сообщений нет.": "Hələ mesaj yoxdur.",
    "Ответ нашедшего": "Tapan şəxsin cavabı",
    "Профиль": "Profil",
    "Без регистрации": "Daxil olunmayıb",
    "Войти через Google": "Daxil ol",
    "Выйти": "Çıxış",
    "Не удалось войти. Повторите попытку.":
        "Daxil olmaq mümkün olmadı. Yenidən cəhd edin.",
    "Не удалось отправить сообщение.": "Mesaj göndərilmədi.",
  },
  "tr": {
    "Приём платежей Zambaruno LLC ещё не подключён.": "Zambaruno LLC için ödeme alma henüz bağlanmadı.",
    "Не удалось открыть оплату. Повторите попытку.": "Ödeme açılamadı. Tekrar deneyin.",

    "Не удалось загрузить находки. Повторить": "Bulunan eşyalar yüklenemedi. Tekrar dene",
    "Это демонстрационный пример. Настоящие находки доступны после входа.": "Bu bir demo örneğidir. Gerçek bulunan eşyaları görmek için giriş yapın.",

    "Камера": "Kamera",
    "Языки": "Diller",
    "Поддержать": "Destek",
    "Лента": "Akış",
    "Переснять": "Yeniden çek",
    "Принять фотографию": "Fotoğrafı kabul et",
    "Язык плаката": "Afiş dili",
    "Оплата пока не подключена.": "Ödeme henüz bağlı değil.",
    "Проверьте электронный адрес.": "E-posta adresinizi kontrol edin.",
    "Подождите минуту перед повторной отправкой.":
        "Tekrar göndermeden önce bir dakika bekleyin.",
    "Не удалось отправить ссылку. Повторите попытку.":
        "Bağlantı gönderilemedi. Tekrar deneyin.",
    "Отправить ссылку": "Bağlantı gönder",
    "Откройте ссылку из письма на этом телефоне.":
        "E-postadaki bağlantıyı bu telefonda açın.",
    "Снимок сохранён на телефоне. Отправим при подключении.":
        "Fotoğraf telefona kaydedildi. Bağlanınca gönderilecek.",
    "Не удалось сохранить фотографию. Повторите попытку.":
        "Fotoğraf kaydedilemedi. Tekrar deneyin.",
    "Не удалось сохранить язык.": "Dil kaydedilemedi.",
    "Войти для просмотра реальных находок":
        "Gerçek buluntuları görmek için giriş yapın",
    "Это моя вещь": "Bu benim eşyam",
    "Возвращено владельцу": "Sahibine iade edildi",
    "У нашедшего": "Bulanda",
    "Передано": "Teslim edildi",
    "Это ваше объявление": "Bu sizin ilanınız",
    "Напишите нашедшему сообщение": "Bulana mesaj yazın",
    "Отмена": "İptal",
    "Отправить": "Gönder",
    "Сообщение отправлено": "Mesaj gönderildi",
    "Куда передана вещь?": "Eşya nereye teslim edildi?",
    "Полиция, бюро находок…": "Polis, kayıp eşya bürosu…",
    "Сохранить": "Kaydet",
    "Находка": "Buluntu",
    "Место находки": "Buluntu yeri",
    "Передано организации": "Kuruma teslim edildi",
    "Сообщения по этой вещи": "Bu eşya hakkındaki mesajlar",
    "Для сообщений войдите по email.": "Mesaj göndermek için giriş yapın.",
    "Ответить": "Yanıtla",
    "Пока сообщений нет.": "Henüz mesaj yok.",
    "Ответ нашедшего": "Bulanın yanıtı",
    "Профиль": "Profil",
    "Без регистрации": "Giriş yapılmadı",
    "Войти через Google": "Giriş yap",
    "Выйти": "Çıkış yap",
    "Не удалось войти. Повторите попытку.": "Giriş yapılamadı. Tekrar deneyin.",
    "Не удалось отправить сообщение.": "Mesaj gönderilemedi.",
  },
  "es": {
    "Приём платежей Zambaruno LLC ещё не подключён.": "Los pagos a Zambaruno LLC aún no están conectados.",
    "Не удалось открыть оплату. Повторите попытку.": "No se pudo abrir el pago. Inténtalo de nuevo.",

    "Не удалось загрузить находки. Повторить": "No se pudieron cargar los objetos. Reintentar",
    "Это демонстрационный пример. Настоящие находки доступны после входа.": "Este es un ejemplo de demostración. Inicia sesión para ver objetos reales.",

    "Камера": "Cámara",
    "Языки": "Idiomas",
    "Поддержать": "Apoyar",
    "Лента": "Galería",
    "Переснять": "Repetir foto",
    "Принять фотографию": "Aceptar foto",
    "Язык плаката": "Idioma del cartel",
    "Оплата пока не подключена.": "Los pagos aún no están conectados.",
    "Проверьте электронный адрес.": "Comprueba tu correo electrónico.",
    "Подождите минуту перед повторной отправкой.":
        "Espera un minuto antes de reenviar.",
    "Не удалось отправить ссылку. Повторите попытку.":
        "No se pudo enviar el enlace. Inténtalo de nuevo.",
    "Отправить ссылку": "Enviar enlace",
    "Откройте ссылку из письма на этом телефоне.":
        "Abre el enlace del correo en este teléfono.",
    "Снимок сохранён на телефоне. Отправим при подключении.":
        "Foto guardada en el teléfono. Se enviará al conectarse.",
    "Не удалось сохранить фотографию. Повторите попытку.":
        "No se pudo guardar la foto. Inténtalo de nuevo.",
    "Не удалось сохранить язык.": "No se pudo guardar el idioma.",
    "Войти для просмотра реальных находок":
        "Inicia sesión para ver hallazgos reales",
    "Это моя вещь": "Esto es mío",
    "Возвращено владельцу": "Devuelto al propietario",
    "У нашедшего": "En poder de quien lo encontró",
    "Передано": "Entregado",
    "Это ваше объявление": "Este es tu anuncio",
    "Напишите нашедшему сообщение": "Escribe a quien lo encontró",
    "Отмена": "Cancelar",
    "Отправить": "Enviar",
    "Сообщение отправлено": "Mensaje enviado",
    "Куда передана вещь?": "¿Dónde se entregó el objeto?",
    "Полиция, бюро находок…": "Policía, oficina de objetos perdidos…",
    "Сохранить": "Guardar",
    "Находка": "Hallazgo",
    "Место находки": "Lugar del hallazgo",
    "Передано организации": "Entregado a una organización",
    "Сообщения по этой вещи": "Mensajes sobre este objeto",
    "Для сообщений войдите по email.": "Inicia sesión para enviar mensajes.",
    "Ответить": "Responder",
    "Пока сообщений нет.": "Aún no hay mensajes.",
    "Ответ нашедшего": "Respuesta de quien lo encontró",
    "Профиль": "Perfil",
    "Без регистрации": "Sin iniciar sesión",
    "Войти через Google": "Iniciar sesión",
    "Выйти": "Cerrar sesión",
    "Не удалось войти. Повторите попытку.":
        "No se pudo iniciar sesión. Inténtalo de nuevo.",
    "Не удалось отправить сообщение.": "No se pudo enviar el mensaje.",
  },
};
