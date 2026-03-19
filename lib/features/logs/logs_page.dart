import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/logging/log_sanitizer.dart';
import '../../data/models/app_log_entry.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String _query = '';
  AppLogLevel? _selectedLevel;
  String? _selectedCategory;
  bool _isExporting = false;
  bool _isSharing = false;
  final Set<String> _expandedPayloadEntries = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsValue = ref.watch(logsControllerProvider);

    return logsValue.when(
      data: (logs) {
        final categories = logs.map((entry) => entry.category).toSet().toList(growable: false)
          ..sort();
        final hasActiveFilters =
            _query.trim().isNotEmpty || _selectedLevel != null || _selectedCategory != null;
        final filtered = logs
            .where((entry) {
              if (_selectedLevel != null && entry.level != _selectedLevel) {
                return false;
              }
              if (_selectedCategory != null && entry.category != _selectedCategory) {
                return false;
              }

              final query = _query.trim().toLowerCase();
              if (query.isEmpty) {
                return true;
              }

              final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
              final sanitizedPayload =
                  LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload) ?? '';
              return sanitizedMessage.toLowerCase().contains(query) ||
                  entry.category.toLowerCase().contains(query) ||
                  (entry.route ?? '').toLowerCase().contains(query) ||
                  sanitizedPayload.toLowerCase().contains(query);
            })
            .toList(growable: false);

        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: SectionHeading(
                title: l10n.logsTitle,
                subtitle: l10n.logsSubtitle,
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      onPressed: filtered.isEmpty || _isExporting || _isSharing
                          ? null
                          : () => _exportLogs(filtered),
                      tooltip: l10n.logsExportTooltip,
                      icon: const Icon(Icons.download_rounded),
                    ),
                    IconButton(
                      onPressed: filtered.isEmpty || _isExporting || _isSharing
                          ? null
                          : () => _shareLogs(filtered),
                      tooltip: l10n.logsShareTooltip,
                      icon: const Icon(Icons.share_rounded),
                    ),
                    IconButton(
                      onPressed: () => ref.read(logsControllerProvider.notifier).refreshState(),
                      tooltip: l10n.logsRefreshButton,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      onPressed: logs.isEmpty ? null : _confirmClearLogs,
                      tooltip: l10n.logsClearButton,
                      style: IconButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.32),
                        ),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: KickPanel(
                tone: KickPanelTone.soft,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: l10n.logsSearchHint,
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        KickBadge(
                          label: l10n.logsTotalCount(logs.length),
                          leading: const Icon(Icons.article_rounded),
                        ),
                        KickBadge(
                          label: l10n.logsFilteredCount(filtered.length),
                          leading: const Icon(Icons.filter_alt_rounded),
                          emphasis: hasActiveFilters,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LogsFilterChip(
                          label: l10n.logsLevelAll,
                          selected: _selectedLevel == null,
                          onSelected: () => setState(() => _selectedLevel = null),
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelInfo,
                          selected: _selectedLevel == AppLogLevel.info,
                          onSelected: () => setState(() => _selectedLevel = AppLogLevel.info),
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelWarning,
                          selected: _selectedLevel == AppLogLevel.warning,
                          onSelected: () => setState(() => _selectedLevel = AppLogLevel.warning),
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelError,
                          selected: _selectedLevel == AppLogLevel.error,
                          onSelected: () => setState(() => _selectedLevel = AppLogLevel.error),
                        ),
                      ],
                    ),
                    if (categories.length > 1) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.logsCategoryFilterTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _LogsFilterChip(
                            label: l10n.logsCategoryAll,
                            selected: _selectedCategory == null,
                            onSelected: () => setState(() => _selectedCategory = null),
                          ),
                          ...categories.map(
                            (category) => _LogsFilterChip(
                              label: category,
                              selected: _selectedCategory == category,
                              onSelected: () => setState(() => _selectedCategory = category),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  child: EmptyStateCard(
                    icon: Icons.article_rounded,
                    title: logs.isEmpty ? l10n.logsEmptyTitle : l10n.logsFilteredEmptyTitle,
                    message: logs.isEmpty ? null : l10n.logsFilteredEmptyMessage,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final itemIndex = index ~/ 2;
                  if (index.isOdd) {
                    return const SizedBox(height: 12);
                  }

                  final entry = filtered[itemIndex];
                  return _LogCard(
                    entry: entry,
                    expandedPayload: _expandedPayloadEntries.contains(entry.id),
                    onCopy: () => _copyLogEntry(entry),
                    onTogglePayload: () => _togglePayload(entry.id),
                  );
                }, childCount: filtered.length * 2 - 1),
              ),
          ],
        );
      },
      error: (error, stackTrace) => EmptyStateCard(
        icon: Icons.error_rounded,
        title: l10n.logsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _exportLogs(List<AppLogEntry> entries) async {
    final l10n = context.l10n;
    if (entries.isEmpty) {
      _showSnackBar(l10n.logsNothingToExportMessage);
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result = await ref
          .read(logExportServiceProvider)
          .export(entries, dialogTitle: l10n.logsExportDialogTitle);
      if (!mounted) {
        return;
      }
      if (result == null) {
        return;
      }
      _showSnackBar(l10n.logsExportedMessage(result.fileName));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.logsExportFailedMessage(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _shareLogs(List<AppLogEntry> entries) async {
    final l10n = context.l10n;
    if (entries.isEmpty) {
      _showSnackBar(l10n.logsNothingToExportMessage);
      return;
    }

    setState(() => _isSharing = true);
    try {
      await ref.read(logExportServiceProvider).share(entries);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.logsShareFailedMessage(error.toString()));
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  Future<void> _confirmClearLogs() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.delete_sweep_rounded),
          title: Text(l10n.logsClearDialogTitle),
          content: Text(l10n.logsClearDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.logsClearConfirmButton),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    _expandedPayloadEntries.clear();
    await ref.read(logsControllerProvider.notifier).clear();
  }

  Future<void> _copyLogEntry(AppLogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: _formatLogEntryForClipboard(entry)));
    if (!mounted) {
      return;
    }
    _showSnackBar(context.l10n.logsCopiedMessage);
  }

  void _togglePayload(String entryId) {
    setState(() {
      if (_expandedPayloadEntries.contains(entryId)) {
        _expandedPayloadEntries.remove(entryId);
      } else {
        _expandedPayloadEntries.add(entryId);
      }
    });
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LogsFilterChip extends StatelessWidget {
  const _LogsFilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onSelected());
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.entry,
    required this.expandedPayload,
    required this.onCopy,
    required this.onTogglePayload,
  });

  final AppLogEntry entry;
  final bool expandedPayload;
  final VoidCallback onCopy;
  final VoidCallback onTogglePayload;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy HH:mm:ss', context.l10n.localeName);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
    final sanitizedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
    final levelColor = switch (entry.level) {
      AppLogLevel.warning => scheme.tertiary,
      AppLogLevel.error => scheme.error,
      AppLogLevel.info => scheme.primary,
    };

    return KickPanel(
      tone: entry.level == AppLogLevel.info ? KickPanelTone.soft : KickPanelTone.muted,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 112,
            decoration: BoxDecoration(color: levelColor, borderRadius: BorderRadius.circular(999)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    KickBadge(
                      label: _logLevelLabel(context.l10n, entry.level),
                      leading: Icon(_logLevelIcon(entry.level), size: 16),
                      emphasis: true,
                      tint: levelColor,
                    ),
                    KickBadge(label: entry.category, leading: const Icon(Icons.label_rounded)),
                    Text(
                      formatter.format(entry.timestamp),
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(sanitizedMessage, style: textTheme.bodyLarge),
                if (entry.route != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    entry.route!,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: Text(context.l10n.logsCopyEntryButton),
                    ),
                    if (sanitizedPayload?.isNotEmpty == true)
                      TextButton.icon(
                        onPressed: onTogglePayload,
                        icon: Icon(
                          expandedPayload ? Icons.unfold_less_rounded : Icons.data_object_rounded,
                          size: 18,
                        ),
                        label: Text(
                          expandedPayload
                              ? context.l10n.logsPayloadHideButton
                              : context.l10n.logsPayloadShowButton,
                        ),
                      ),
                  ],
                ),
                if (expandedPayload && sanitizedPayload?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    sanitizedPayload!,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _logLevelLabel(KickLocalizations l10n, AppLogLevel level) {
  return switch (level) {
    AppLogLevel.info => l10n.logsEntryLevelInfo,
    AppLogLevel.warning => l10n.logsEntryLevelWarning,
    AppLogLevel.error => l10n.logsEntryLevelError,
  };
}

IconData _logLevelIcon(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.info => Icons.info_rounded,
    AppLogLevel.warning => Icons.warning_amber_rounded,
    AppLogLevel.error => Icons.error_rounded,
  };
}

String _formatLogEntryForClipboard(AppLogEntry entry) {
  final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
  final sanitizedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
  final buffer = StringBuffer()
    ..writeln('[${entry.level.name.toUpperCase()}] ${entry.category}')
    ..writeln('Time: ${entry.timestamp.toIso8601String()}')
    ..writeln(sanitizedMessage);

  if (entry.route?.trim().isNotEmpty == true) {
    buffer.writeln('Route: ${entry.route}');
  }
  if (sanitizedPayload?.trim().isNotEmpty == true) {
    buffer
      ..writeln()
      ..writeln(sanitizedPayload);
  }

  return buffer.toString().trimRight();
}
