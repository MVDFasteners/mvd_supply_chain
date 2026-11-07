import 'package:flutter_test/flutter_test.dart';
import 'package:mvdsupplychain/main.dart';

void main() {
  test('app configuration points at the production storefront', () {
    expect(kAppName, 'MVD Supply Chain');
    expect(kHomeUrl, 'https://mvdsupplychain.com/shop-cart/');
    expect(kHomeUrl.startsWith('https://'), isTrue);
  });
}
