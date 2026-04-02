import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/proxy/model_catalog.dart';

void main() {
  test('preserves exact model ids when merging bundled and custom models', () {
    final catalog = ModelCatalog(
      customModels: const [
        'models/gemini-2.5-flash',
        'google/gemini-3-flash',
        'google/gemini-4-experimental-preview',
      ],
    );

    final models = catalog.all();

    expect(models, contains('google/gemini-2.5-flash'));
    expect(models, contains('google/gemini-3-flash'));
    expect(models, contains('google/gemini-4-experimental-preview'));
    expect(models.where((item) => item == 'google/gemini-2.5-flash').length, 1);
    expect(catalog.contains('google/gemini-3-flash'), isTrue);
  });

  test('keeps model listing and routing provider-aware', () {
    final catalog = ModelCatalog(
      customModels: const ['kiro/deepseek-chat', 'google/gemini-4-experimental-preview'],
      kiroModels: const ['auto', 'deepseek-3.2', 'minimax-m2.5'],
      enableGemini: false,
      enableKiro: true,
    );

    final models = catalog.all();
    final resolved = catalog.resolve('deepseek-3.2');

    expect(models, contains('kiro/auto'));
    expect(models, contains('kiro/deepseek-3.2'));
    expect(models, contains('kiro/minimax-m2.5'));
    expect(models, contains('kiro/deepseek-chat'));
    expect(models, isNot(contains('google/gemini-4-experimental-preview')));
    expect(catalog.contains('deepseek-3.2'), isTrue);
    expect(catalog.contains('kiro/qwen3-coder-next'), isTrue);
    expect(catalog.contains('gemini-2.5-flash'), isFalse);
    expect(resolved.provider, AccountProvider.kiro);
    expect(resolved.upstreamModel, 'deepseek-3.2');
    expect(resolved.publicModel, 'kiro/deepseek-3.2');
  });

  test('does not advertise hardcoded Kiro models when discovery is empty', () {
    final catalog = ModelCatalog(customModels: const [], enableGemini: false, enableKiro: true);

    expect(catalog.all(), isEmpty);
    expect(catalog.contains('kiro/deepseek-3.2'), isTrue);
  });

  test('builds canonical provider/model ids for user-facing storage', () {
    expect(
      ModelCatalog.normalizePublicModel('gemini-3.1-pro', defaultProvider: AccountProvider.gemini),
      'google/gemini-3.1-pro',
    );
    expect(
      ModelCatalog.normalizePublicModel('claude-opus-4.5', defaultProvider: AccountProvider.kiro),
      'kiro/claude-opus-4.5',
    );
  });
}
