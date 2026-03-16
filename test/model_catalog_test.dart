import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/model_catalog.dart';

void main() {
  test('normalizes and merges bundled and custom models', () {
    final catalog = ModelCatalog(
      customModels: const [
        'models/gemini-2.5-flash',
        'gemini-3-flash',
        'gemini-4-experimental-preview',
      ],
    );

    final models = catalog.all();

    expect(models, contains('gemini-2.5-flash'));
    expect(models, contains('gemini-3-flash-preview'));
    expect(models, isNot(contains('gemini-3-flash')));
    expect(models, contains('gemini-4-experimental-preview'));
    expect(models.where((item) => item == 'gemini-2.5-flash').length, 1);
    expect(catalog.contains('gemini-3-flash'), isTrue);
  });
}
