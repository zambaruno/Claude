import 'package:flutter_test/flutter_test.dart';
import 'package:lost_mvp/support_payments.dart';

void main() {
  test('PayPal opens the receiving profile with exact USD amount', () {
    for (final amount in [1, 500, 1000, 2000, 5000, 10000]) {
      expect(supportPaymentUri(PaymentSelection(amount, PaymentMethod.paypal),
        paypal: 'https://paypal.me/ExampleReceiver').toString(),
        'https://paypal.me/ExampleReceiver/${amount}USD');
    }
  });
  test('card and wallets use the amount-specific hosted checkout', () {
    for (final method in [PaymentMethod.card, PaymentMethod.googlePay, PaymentMethod.applePay]) {
      expect(supportPaymentUri(PaymentSelection(500, method),
        checkout: '{"500":"https://buy.stripe.com/test_example"}').toString(),
        'https://buy.stripe.com/test_example');
    }
  });
  test('missing or untrusted receiving links cannot open checkout', () {
    for (final url in ['', 'http://paypal.me/Example', 'https://paypal.me.attacker.test/Example']) {
      expect(() => supportPaymentUri(const PaymentSelection(1, PaymentMethod.paypal), paypal: url),
        throwsA(isA<PaymentSetupException>()));
    }
    expect(() => supportPaymentUri(const PaymentSelection(2, PaymentMethod.googlePay),
      checkout: '{"1":"https://buy.stripe.com/test_example"}'),
      throwsA(isA<PaymentSetupException>()));
    expect(() => supportPaymentUri(const PaymentSelection(1, PaymentMethod.card),
      checkout: '{"1":"https://example.org/pay"}'),
      throwsA(isA<PaymentSetupException>()));
    expect(() => supportPaymentUri(const PaymentSelection(1, PaymentMethod.card), checkout: 'bad json'),
      throwsA(isA<PaymentSetupException>()));
  });
}
