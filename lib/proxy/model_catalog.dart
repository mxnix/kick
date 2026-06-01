import '../data/models/account_profile.dart';

class ResolvedProxyModel {
  const ResolvedProxyModel({
    required this.provider,
    required this.upstreamModel,
    required this.publicModel,
    required this.explicitProvider,
  });

  final AccountProvider provider;
  final String upstreamModel;
  final String publicModel;
  final bool explicitProvider;
}

class _ParsedModelReference {
  const _ParsedModelReference({
    required this.modelId,
    required this.explicitProvider,
    this.provider,
  });

  final AccountProvider? provider;
  final String modelId;
  final bool explicitProvider;
}

class ModelCatalog {
  ModelCatalog({
    required List<String> customModels,
    List<String> geminiModels = const [],
    List<String> kiroModels = const [],
    List<String> lumaModels = const [],
    bool enableGemini = true,
    bool? enableKiro,
    bool? enableLuma,
  }) : _customModels = customModels,
       _geminiModels = geminiModels,
       _kiroModels = kiroModels,
       _lumaModels = lumaModels,
       _enableGemini = enableGemini,
       _enableKiro = enableKiro ?? kiroModels.isNotEmpty,
       _enableLuma = enableLuma ?? lumaModels.isNotEmpty;

  static const String googleProviderId = 'google';
  static const String kiroProviderId = 'kiro';
  static const String lumaProviderId = 'luma';

  final List<String> _customModels;
  final List<String> _geminiModels;
  final List<String> _kiroModels;
  final List<String> _lumaModels;
  final bool _enableGemini;
  final bool _enableKiro;
  final bool _enableLuma;

  List<String> all() {
    final values = <String>{};
    if (_enableGemini) {
      values.addAll({
        for (final model in _geminiPublicModels) _publicModelId(AccountProvider.gemini, model),
      });
    }
    if (_enableKiro) {
      values.addAll({
        for (final model in _publicKiroModels) _publicModelId(AccountProvider.kiro, model),
      });
    }
    if (_enableLuma) {
      values.addAll({
        for (final model in _publicLumaModels) _publicModelId(AccountProvider.luma, model),
        for (final model in _publicLumaModels) model,
      });
    }
    final list = values.where((item) => item.isNotEmpty).toList()..sort();
    return list;
  }

  static String normalizeModel(String model) {
    final parsed = _parseModelReference(model);
    return _normalizeForProvider(parsed.modelId, parsed.provider ?? AccountProvider.gemini);
  }

  static String normalizePublicModel(String model, {AccountProvider? defaultProvider}) {
    final parsed = _parseModelReference(model);
    final provider = parsed.provider ?? defaultProvider ?? _inferProvider(parsed.modelId);
    final trimmed = parsed.modelId.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (provider == null) {
      return trimmed;
    }
    return _publicModelId(provider, _normalizeForProvider(trimmed, provider));
  }

  String normalize(String model) => normalizeModel(model);

  bool contains(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final parsed = _parseModelReference(trimmed);
    if (parsed.provider case final explicitProvider?) {
      if (!_providerEnabled(explicitProvider)) {
        return false;
      }
      if (explicitProvider == AccountProvider.kiro) {
        return parsed.modelId.trim().isNotEmpty;
      }
      if (explicitProvider == AccountProvider.luma) {
        return parsed.modelId.trim().isNotEmpty;
      }
      final normalized = _normalizeForProvider(parsed.modelId, explicitProvider);
      if (_providerModels(explicitProvider).contains(normalized)) {
        return true;
      }
      return _isLikelyProviderModel(explicitProvider, normalized);
    }

    final geminiModel = _normalizeForProvider(parsed.modelId, AccountProvider.gemini);
    if (_geminiKnownModels.contains(geminiModel)) {
      return true;
    }

    final kiroModel = _normalizeForProvider(parsed.modelId, AccountProvider.kiro);
    if (_kiroKnownModels.contains(kiroModel)) {
      return true;
    }

    final lumaModel = _normalizeForProvider(parsed.modelId, AccountProvider.luma);
    if (_lumaKnownModels.contains(lumaModel)) {
      return true;
    }

    if (_enableLuma && _isLikelyProviderModel(AccountProvider.luma, lumaModel)) {
      return true;
    }

    if (_enableKiro && _isLikelyProviderModel(AccountProvider.kiro, kiroModel)) {
      return true;
    }

    return _enableGemini && _isLikelyProviderModel(AccountProvider.gemini, geminiModel);
  }

  ResolvedProxyModel resolve(String model) {
    final parsed = _parseModelReference(model);
    if (parsed.provider case final explicitProvider?) {
      final normalized = _normalizeForProvider(parsed.modelId, explicitProvider);
      return ResolvedProxyModel(
        provider: explicitProvider,
        upstreamModel: normalized,
        publicModel: _publicModelId(explicitProvider, normalized),
        explicitProvider: true,
      );
    }

    final geminiModel = _normalizeForProvider(parsed.modelId, AccountProvider.gemini);
    final kiroModel = _normalizeForProvider(parsed.modelId, AccountProvider.kiro);
    final lumaModel = _normalizeForProvider(parsed.modelId, AccountProvider.luma);
    final geminiKnown = _geminiKnownModels.contains(geminiModel);
    final kiroKnown = _kiroKnownModels.contains(kiroModel);
    final lumaKnown = _lumaKnownModels.contains(lumaModel);

    if (lumaKnown && !geminiKnown && !kiroKnown) {
      return ResolvedProxyModel(
        provider: AccountProvider.luma,
        upstreamModel: lumaModel,
        publicModel: _publicModelId(AccountProvider.luma, lumaModel),
        explicitProvider: false,
      );
    }
    if (geminiKnown && !kiroKnown) {
      return ResolvedProxyModel(
        provider: AccountProvider.gemini,
        upstreamModel: geminiModel,
        publicModel: _publicModelId(AccountProvider.gemini, geminiModel),
        explicitProvider: false,
      );
    }
    if (kiroKnown && !geminiKnown) {
      return ResolvedProxyModel(
        provider: AccountProvider.kiro,
        upstreamModel: kiroModel,
        publicModel: _publicModelId(AccountProvider.kiro, kiroModel),
        explicitProvider: false,
      );
    }
    if (kiroKnown && _isLikelyProviderModel(AccountProvider.kiro, kiroModel)) {
      return ResolvedProxyModel(
        provider: AccountProvider.kiro,
        upstreamModel: kiroModel,
        publicModel: _publicModelId(AccountProvider.kiro, kiroModel),
        explicitProvider: false,
      );
    }
    if (_isLikelyProviderModel(AccountProvider.luma, lumaModel)) {
      return ResolvedProxyModel(
        provider: AccountProvider.luma,
        upstreamModel: lumaModel,
        publicModel: _publicModelId(AccountProvider.luma, lumaModel),
        explicitProvider: false,
      );
    }
    if (_isLikelyProviderModel(AccountProvider.kiro, kiroModel)) {
      return ResolvedProxyModel(
        provider: AccountProvider.kiro,
        upstreamModel: kiroModel,
        publicModel: _publicModelId(AccountProvider.kiro, kiroModel),
        explicitProvider: false,
      );
    }

    return ResolvedProxyModel(
      provider: AccountProvider.gemini,
      upstreamModel: geminiModel,
      publicModel: _publicModelId(AccountProvider.gemini, geminiModel),
      explicitProvider: false,
    );
  }

  Map<String, Object?> toOpenAiModelList() {
    return {
      'object': 'list',
      'data': [
        for (final model in all())
          {'id': model, 'object': 'model', 'created': 0, 'owned_by': 'kick', 'display_name': model},
      ],
    };
  }

  Set<String> get _geminiPublicModels => {
    for (final model in _geminiModels) _normalizeForProvider(model, AccountProvider.gemini),
    for (final model in _customModels)
      if (!_parseModelReference(model).explicitProvider ||
          _parseModelReference(model).provider == AccountProvider.gemini)
        _normalizeForProvider(_parseModelReference(model).modelId, AccountProvider.gemini),
  };

  Set<String> get _publicKiroModels => {
    for (final model in _kiroModels) _normalizeForProvider(model, AccountProvider.kiro),
    for (final model in _customModels)
      if (_parseModelReference(model).provider == AccountProvider.kiro)
        _normalizeForProvider(_parseModelReference(model).modelId, AccountProvider.kiro),
  };

  Set<String> get _publicLumaModels => {
    for (final model in _lumaModels) _normalizeForProvider(model, AccountProvider.luma),
    for (final model in _customModels)
      if (_parseModelReference(model).provider == AccountProvider.luma)
        _normalizeForProvider(_parseModelReference(model).modelId, AccountProvider.luma),
  };

  Set<String> get _geminiKnownModels => _enableGemini ? _geminiPublicModels : const <String>{};

  Set<String> get _kiroKnownModels => _enableKiro ? _publicKiroModels : const <String>{};

  Set<String> get _lumaKnownModels => _enableLuma ? _publicLumaModels : const <String>{};

  Set<String> _providerModels(AccountProvider provider) {
    return switch (provider) {
      AccountProvider.antigravity => _geminiKnownModels,
      AccountProvider.kiro => _kiroKnownModels,
      AccountProvider.luma => _lumaKnownModels,
    };
  }

  bool _providerEnabled(AccountProvider provider) {
    return switch (provider) {
      AccountProvider.antigravity => _enableGemini,
      AccountProvider.kiro => _enableKiro,
      AccountProvider.luma => _enableLuma,
    };
  }

  static _ParsedModelReference _parseModelReference(String model) {
    var trimmed = model.trim();
    if (trimmed.startsWith('models/')) {
      trimmed = trimmed.substring('models/'.length);
    }

    final slash = trimmed.indexOf('/');
    if (slash > 0) {
      final provider = _providerFromToken(trimmed.substring(0, slash));
      if (provider != null) {
        return _ParsedModelReference(
          provider: provider,
          modelId: trimmed.substring(slash + 1).trim(),
          explicitProvider: true,
        );
      }
    }

    final separator = trimmed.indexOf(':');
    if (separator > 0) {
      final provider = _providerFromToken(trimmed.substring(0, separator));
      if (provider != null) {
        return _ParsedModelReference(
          provider: provider,
          modelId: trimmed.substring(separator + 1).trim(),
          explicitProvider: true,
        );
      }
    }

    return _ParsedModelReference(modelId: trimmed, explicitProvider: false);
  }

  static AccountProvider? _providerFromToken(String token) {
    return switch (token.trim().toLowerCase()) {
      'google' || 'gemini' || 'antigravity' => AccountProvider.antigravity,
      'kiro' => AccountProvider.kiro,
      'luma' || 'lumalabs' => AccountProvider.luma,
      _ => null,
    };
  }

  static AccountProvider? _inferProvider(String model) {
    if (_isLikelyProviderModel(AccountProvider.kiro, model)) {
      return AccountProvider.kiro;
    }
    if (_isLikelyProviderModel(AccountProvider.gemini, model)) {
      return AccountProvider.gemini;
    }
    if (_isLikelyProviderModel(AccountProvider.luma, model)) {
      return AccountProvider.luma;
    }
    return null;
  }

  static String _normalizeForProvider(String model, AccountProvider provider) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed;
  }

  static String _publicModelId(AccountProvider provider, String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final providerId = switch (provider) {
      AccountProvider.antigravity => googleProviderId,
      AccountProvider.kiro => kiroProviderId,
      AccountProvider.luma => lumaProviderId,
    };
    return '$providerId/$trimmed';
  }

  static bool _isLikelyProviderModel(AccountProvider provider, String model) {
    final normalized = model.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return switch (provider) {
      AccountProvider.antigravity =>
        normalized.startsWith('gemini-') ||
            normalized.startsWith('claude-') ||
            normalized.startsWith('gpt-oss-'),
      AccountProvider.kiro =>
        normalized == 'auto' ||
            normalized == 'simple-task' ||
            normalized.startsWith('claude-') ||
            normalized.startsWith('anthropic.') ||
            normalized.startsWith('deepseek-') ||
            normalized.startsWith('minimax-') ||
            normalized.startsWith('qwen'),
      AccountProvider.luma =>
        normalized.startsWith('nano-banana') ||
            normalized.startsWith('gpt-image') ||
            normalized == 'seedream' ||
            normalized.startsWith('uni-image-') ||
            normalized.startsWith('uni-'),
    };
  }
}
