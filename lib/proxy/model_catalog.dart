class ModelCatalog {
  ModelCatalog({required List<String> customModels}) : _customModels = customModels;

  static const Map<String, String> aliases = {
    'gemini-3.1-flash-lite': 'gemini-3.1-flash-lite-preview',
    'gemini-3.1-pro': 'gemini-3.1-pro-preview',
    'gemini-3-pro': 'gemini-3-pro-preview',
    'gemini-3-flash': 'gemini-3-flash-preview',
    'gemini-2.5-pro-preview': 'gemini-2.5-pro',
    'gemini-2.5-flash-preview': 'gemini-2.5-flash',
  };

  static const List<String> bundledModels = [
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-3-pro-preview',
    'gemini-3-flash-preview',
    'gemini-3.1-pro-preview',
    'gemini-3.1-flash-lite-preview',
  ];

  final List<String> _customModels;

  List<String> all() {
    final values = <String>{
      for (final model in bundledModels) normalize(model),
      for (final model in _customModels) normalize(model),
    };
    final list = values.where((item) => item.isNotEmpty).toList()..sort();
    return list;
  }

  static String normalizeModel(String model) {
    final trimmed = model.trim();
    if (trimmed.startsWith('models/')) {
      return normalizeModel(trimmed.substring('models/'.length));
    }
    return aliases[trimmed] ?? trimmed;
  }

  String normalize(String model) => normalizeModel(model);

  bool contains(String model) => all().contains(normalize(model));

  Map<String, Object?> toOpenAiModelList() {
    return {
      'object': 'list',
      'data': [
        for (final model in all())
          {'id': model, 'object': 'model', 'created': 0, 'owned_by': 'kick', 'display_name': model},
      ],
    };
  }
}
