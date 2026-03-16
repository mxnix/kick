import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/accounts/account_priority.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';

class AccountEditorResult {
  const AccountEditorResult({
    required this.projectId,
    required this.label,
    required this.priority,
    required this.notSupportedModels,
  });

  final String projectId;
  final String label;
  final int priority;
  final List<String> notSupportedModels;
}

Future<AccountEditorResult?> showAccountEditorDialog(
  BuildContext context, {
  AccountProfile? initial,
  String? title,
}) {
  return showDialog<AccountEditorResult>(
    context: context,
    builder: (context) => _AccountEditorDialog(initial: initial, title: title),
  );
}

class _AccountEditorDialog extends StatefulWidget {
  const _AccountEditorDialog({this.initial, this.title});

  final AccountProfile? initial;
  final String? title;

  @override
  State<_AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<_AccountEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _projectController;
  late final TextEditingController _labelController;
  late final TextEditingController _modelsController;
  late AccountPriorityLevel _selectedPriority;

  @override
  void initState() {
    super.initState();
    _projectController = TextEditingController(text: widget.initial?.projectId ?? '');
    _labelController = TextEditingController(text: widget.initial?.label ?? '');
    _modelsController = TextEditingController(
      text: widget.initial?.notSupportedModels.join('\n') ?? '',
    );
    _selectedPriority = AccountPriorityLevel.fromStoredValue(
      widget.initial?.priority ?? AccountPriorityLevel.normal.storedValue,
    );
  }

  @override
  void dispose() {
    _projectController.dispose();
    _labelController.dispose();
    _modelsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                TextFormField(
                  controller: _projectController,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) {
                    return value?.trim().isEmpty == true ? l10n.projectIdRequiredError : null;
                  },
                  decoration: InputDecoration(
                    labelText: l10n.projectIdLabel,
                    hintText: l10n.projectIdHint,
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
                const SizedBox(height: 14),
                TextField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    labelText: l10n.accountNameLabel,
                    hintText: l10n.accountNameHint,
                  ),
                ),
                const SizedBox(height: 14),
                Text(l10n.priorityLabel, style: Theme.of(context).textTheme.titleSmall),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
    if (!opened || !mounted) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectIdLookupFailedMessage)));
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      AccountEditorResult(
        projectId: _projectController.text.trim(),
        label: _labelController.text.trim(),
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
