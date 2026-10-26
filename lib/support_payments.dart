import 'dart:convert';

enum PaymentMethod { googlePay, paypal, card, applePay }

class PaymentSelection {
  const PaymentSelection(this.amountUsd, this.method);
  final int amountUsd;
  final PaymentMethod method;
}

class PaymentSetupException implements Exception {
  const PaymentSetupException(this.method);
  final PaymentMethod method;
}

// Public receiving links only. Secret provider keys must never enter the APK.
const paypalMe = String.fromEnvironment('LOST_PAYPAL_ME');
const checkoutLinks = String.fromEnvironment('LOST_CHECKOUT_LINKS', defaultValue: '{}');

Uri supportPaymentUri(
  PaymentSelection selection, {
  String paypal = paypalMe,
  String checkout = checkoutLinks,
}) {
  const amounts = {1, 2, 3, 5, 10, 20, 50, 100, 500, 1000, 2000, 5000, 10000};
  if (!amounts.contains(selection.amountUsd)) {
    throw ArgumentError.value(selection.amountUsd, 'amountUsd');
  }
  if (selection.method == PaymentMethod.paypal) {
    final base = Uri.tryParse(paypal.trim());
    if (base != null && base.scheme == 'https' &&
        base.host == 'paypal.me' && base.userInfo.isEmpty &&
        base.port == 443 && base.query.isEmpty && base.fragment.isEmpty &&
        base.pathSegments.length == 1 &&
        RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(base.pathSegments.single)) {
      return Uri.https('paypal.me', '${base.pathSegments.single}/${selection.amountUsd}USD');
    }
  } else {
    // Each Stripe Payment Link fixes its amount/currency on the provider side.
    // Google Pay / Apple Pay are offered by hosted checkout when supported.
    try {
      final links = jsonDecode(checkout);
      final value = links is Map ? links['${selection.amountUsd}'] : null;
      final uri = value is String ? Uri.tryParse(value) : null;
      if (uri != null && uri.scheme == 'https' &&
          uri.host == 'buy.stripe.com' && uri.userInfo.isEmpty &&
          uri.port == 443 && uri.pathSegments.isNotEmpty &&
          uri.fragment.isEmpty) return uri;
    } on FormatException {
      // Treat invalid build configuration as unavailable, never as a payment.
    }
  }
  throw PaymentSetupException(selection.method);
}
