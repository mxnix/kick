import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/proxy/model_catalog.dart';

void main() {
  test('exposes Luma static models when enableLuma is true', () {
    final catalog = ModelCatalog(
      customModels: const [],
      enableGemini: false,
      enableKiro: false,
      enableLuma: true,
      lumaModels: const [
        'nano-banana-pro',
        'nano-banana-2',
        'gpt-image-2',
        'gpt-image-1.5',
        'seedream',
        'uni-1.1',
        'uni-image-1.1',
      ],
    );

    final models = catalog.all();

    expect(models, contains('nano-banana-pro'));
    expect(models, contains('gpt-image-2'));
    expect(models, contains('seedream'));
    expect(models, contains('uni-image-1.1'));
    expect(models, contains('luma/nano-banana-pro'));
    expect(models, contains('luma/nano-banana-2'));
    expect(models, contains('luma/gpt-image-2'));
    expect(models, contains('luma/seedream'));
    expect(models, contains('luma/uni-1.1'));
    expect(models, contains('luma/uni-image-1.1'));
    expect(models, isNot(contains('uni-1')));
  });

  test('hides Luma models when enableLuma is false', () {
    final catalog = ModelCatalog(
      customModels: const [],
      enableGemini: false,
      enableKiro: false,
      enableLuma: false,
      lumaModels: const ['nano-banana-pro'],
    );

    expect(catalog.all(), isEmpty);
    expect(catalog.contains('luma/nano-banana-pro'), isFalse);
  });

  test('routes bare Luma model ids to the Luma provider', () {
    final catalog = ModelCatalog(
      customModels: const [],
      enableGemini: false,
      enableKiro: false,
      enableLuma: true,
      lumaModels: const ['nano-banana-pro', 'seedream'],
    );

    final resolved = catalog.resolve('seedream');
    expect(resolved.provider, AccountProvider.luma);
    expect(resolved.publicModel, 'luma/seedream');
  });

  test('routes SillyTavern-compatible Uni image alias to the Luma provider', () {
    final catalog = ModelCatalog(
      customModels: const [],
      enableGemini: false,
      enableKiro: false,
      enableLuma: true,
      lumaModels: const ['uni-image-1.1'],
    );

    final resolved = catalog.resolve('uni-image-1.1');
    expect(catalog.contains('uni-image-1.1'), isTrue);
    expect(resolved.provider, AccountProvider.luma);
    expect(resolved.publicModel, 'luma/uni-image-1.1');
  });
}
