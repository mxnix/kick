import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/accounts/account_priority.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/kiro/kiro_auth_source.dart';
import '../shared/provider_icon.dart';

class AccountEditorResult {
  const AccountEditorResult({
    required this.provider,
    required this.projectId,
    required this.label,
    required this.kiroBuilderIdStartUrl,
    required this.kiroRegion,
    required this.priority,
    required this.notSupportedModels,
  });

  final AccountProvider provider;
  final String projectId;
  final String label;
  final String kiroBuilderIdStartUrl;
  final String kiroRegion;
  final int priority;
  final List<String> notSupportedModels;
}

Future<AccountEditorResult?> showAccountEditorDialog(
  BuildContext context, {
  AccountProfile? initial,
  AccountProvider? provider,
  String? title,
}) {
  return showDialog<AccountEditorResult>(
    context: context,
    builder: (context) => _AccountEditorDialog(initial: initial, provider: provider, title: title),
  );
}

class _AccountEditorDialog extends StatefulWidget {
  const _AccountEditorDialog({this.initial, this.provider, this.title});

  final AccountProfile? initial;
  final AccountProvider? provider;
  final String? title;

  @override
  State<_AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<_AccountEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _projectController;
  late final TextEditingController _labelController;
  late final TextEditingController _kiroBuilderIdStartUrlController;
  late final TextEditingController _kiroRegionController;
  late final TextEditingController _modelsController;
  late AccountProvider _selectedProvider;
  late AccountPriorityLevel _selectedPriority;
  late bool _advancedExpanded;

  bool get _providerLocked => widget.initial != null || widget.provider != null;

  @override
  void initState() {
    super.initState();
    _projectController = TextEditingController(text: widget.initial?.projectId ?? '');
    _labelController = TextEditingController(text: widget.initial?.label ?? '');
    _kiroBuilderIdStartUrlController = TextEditingController(text: defaultKiroBuilderIdStartUrl);
    _kiroRegionController = TextEditingController(
      text: widget.initial?.providerRegion ?? defaultKiroRegion,
    );
    _modelsController = TextEditingController(
      text: widget.initial?.notSupportedModels.join('\n') ?? '',
    );
    _selectedProvider = widget.initial?.provider ?? widget.provider ?? AccountProvider.gemini;
    _selectedPriority = AccountPriorityLevel.fromStoredValue(
      widget.initial?.priority ?? AccountPriorityLevel.normal.storedValue,
    );
    _advancedExpanded =
        widget.initial != null &&
        (_selectedPriority != AccountPriorityLevel.normal ||
            (widget.initial?.notSupportedModels.isNotEmpty ?? false));
  }

  @override
  void dispose() {
    _projectController.dispose();
    _labelController.dispose();
    _kiroBuilderIdStartUrlController.dispose();
    _kiroRegionController.dispose();
    _modelsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final providerLabel = switch (_selectedProvider) {
      AccountProvider.gemini => l10n.accountProviderGemini,
      AccountProvider.kiro => l10n.accountProviderKiro,
      AccountProvider.luma => l10n.accountProviderLuma,
    };

    return AlertDialog(
      icon: const Icon(Icons.account_circle_rounded),
      title: Text(widget.title ?? l10n.accountDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.accountDialogBasicsTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  l10n.accountDialogBasicsSubtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                if (_providerLocked) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
                    ),
                    child: Row(
                      children: [
                        ProviderIcon(
                          provider: _selectedProvider,
                          size: 24,
                          variant: ProviderIconVariant.brand,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.accountProviderLabel,
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Text(providerLabel, style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.accountProviderLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AccountProvider>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: AccountProvider.gemini,
                          label: Text(l10n.accountProviderGemini),
                        ),
                        ButtonSegment(
                          value: AccountProvider.kiro,
                          label: Text(l10n.accountProviderKiro),
                        ),
                        ButtonSegment(
                          value: AccountProvider.luma,
                          label: Text(l10n.accountProviderLuma),
                        ),
                      ],
                      selected: {_selectedProvider},
                      onSelectionChanged: (value) {
                        setState(() => _selectedProvider = value.first);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (_selectedProvider == AccountProvider.gemini) ...[
                  TextFormField(
                    controller: _projectController,
                    decoration: InputDecoration(
                      labelText: l10n.projectIdLabel,
                      hintText: l10n.projectIdHint,
                      helperText: l10n.projectIdOptionalHelperText,
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _openProjectConsole,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l10n.projectIdConsoleLinkLabel),
                  ),
                ] else if (_selectedProvider == AccountProvider.luma) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 18, color: scheme.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.accountLumaComingSoonHelperText,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _kiroBuilderIdStartUrlController,
                    decoration: InputDecoration(
                      labelText: l10n.kiroBuilderIdStartUrlLabel,
                      hintText: defaultKiroBuilderIdStartUrl,
                      helperText: l10n.kiroBuilderIdStartUrlHelperText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _kiroRegionController,
                    decoration: InputDecoration(
                      labelText: l10n.kiroRegionLabel,
                      hintText: defaultKiroRegion,
                      helperText: l10n.kiroRegionHelperText,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    labelText: l10n.accountNameLabel,
                    hintText: l10n.accountNameHint,
                    helperText: l10n.accountNameHelperText,
                  ),
                ),
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: _advancedExpanded,
                    onExpansionChanged: (value) {
                      setState(() => _advancedExpanded = value);
                    },
                    tilePadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    title: Text(
                      l10n.accountDialogAdvancedTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      l10n.accountDialogAdvancedSubtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.accountDialogAdvancedHint,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.priorityLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<AccountPriorityLevel>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: AccountPriorityLevel.primary,
                            label: Text(l10n.priorityLevelPrimary),
                          ),
                          ButtonSegment(
                            value: AccountPriorityLevel.normal,
                            label: Text(l10n.priorityLevelNormal),
                          ),
                          ButtonSegment(
                            value: AccountPriorityLevel.reserve,
                            label: Text(l10n.priorityLevelReserve),
                          ),
                        ],
                        selected: {_selectedPriority},
                        onSelectionChanged: (value) {
                          setState(() => _selectedPriority = value.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.priorityHelperText,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _modelsController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: l10n.blockedModelsLabel,
                          helperText: l10n.blockedModelsHelperText,
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(onPressed: _submit, child: Text(l10n.continueButton)),
      ],
    );
  }

  Future<void> _openProjectConsole() async {
    final opened = await launchUrl(
      Uri.parse('https://console.cloud.google.com/'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.projectIdLookupFailedMessage)));
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      AccountEditorResult(
        provider: _selectedProvider,
        projectId: _projectController.text.trim(),
        label: _labelController.text.trim(),
        kiroBuilderIdStartUrl: _kiroBuilderIdStartUrlController.text.trim(),
        kiroRegion: _kiroRegionController.text.trim(),
        priority: _selectedPriority.storedValue,
        notSupportedModels: _modelsController.text
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      ),
    );
  }
}
