import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/logging/log_sanitizer.dart';
import '../../core/theme/kick_icons.dart';
import '../../core/theme/kick_theme.dart';
import '../../data/models/app_log_entry.dart';
import '../../l10n/kick_localizations.dart';
import '../app_shell/app_shell.dart';
import '../app_state/providers.dart';
import '../shared/kick_actions.dart';
import '../shared/kick_haptics.dart';
import '../shared/kick_scroll.dart';
import '../shared/kick_surfaces.dart';
import 'log_display_items.dart';
import 'log_export_service.dart';
import 'log_message_localizer.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  bool _isExporting = false;
  bool _isSharing = false;
  final Set<String> _expandedRequestEntries = <String>{};
  final Set<String> _expandedPayloadEntries = <String>{};
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsValue = ref.watch(logsControllerProvider);

    return logsValue.when(
      data: (logs) {
        if (_searchController.text != logs.query) {
          _searchController.value = TextEditingValue(
            text: logs.query,
            selection: TextSelection.collapsed(offset: logs.query.length),
          );
        }
        final entries = logs.entries;
        final displayItems = logs.displayItems;
        return KickSmoothCustomScrollView(
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
                    KickIconAction(
                      onPressed: logs.filteredCount == 0 || _isExporting || _isSharing
                          ? null
                          : _exportLogs,
                      tooltip: l10n.logsExportTooltip,
                      icon: KickIcons.download,
                    ),
                    KickIconAction(
                      onPressed: logs.filteredCount == 0 || _isExporting || _isSharing
                          ? null
                          : _shareLogs,
                      tooltip: l10n.logsShareTooltip,
                      icon: KickIcons.share,
                    ),
                    KickIconAction(
                      onPressed: logs.totalCount == 0 ? null : _confirmClearLogs,
                      tooltip: l10n.logsClearButton,
                      icon: KickIcons.deleteSweep,
                      dangerous: true,
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
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(KickIcons.search),
                        hintText: l10n.logsSearchHint,
                        suffixIcon: logs.query.trim().isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  unawaited(
                                    ref.read(logsControllerProvider.notifier).updateQuery(''),
                                  );
                                },
                                tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                                icon: const Icon(KickIcons.clear),
                              ),
                      ),
                      onChanged: (value) {
                        unawaited(ref.read(logsControllerProvider.notifier).updateQuery(value));
                      },
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        KickBadge(
                          label: l10n.logsTotalCount(logs.totalCount),
                          leading: const Icon(KickIcons.logs),
                        ),
                        AnimatedSwitcher(
                          duration:
                              Theme.of(context).extension<KickThemeTokens>()?.shortDuration ??
                              const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) => SizeTransition(
                            sizeFactor: animation,
                            axis: Axis.horizontal,
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                          child: logs.hasActiveFilters
                              ? KickBadge(
                                  key: const ValueKey('logs-filtered-count'),
                                  label: l10n.logsFilteredCount(logs.filteredCount),
                                  leading: const Icon(KickIcons.filter),
                                  emphasis: true,
                                )
                              : const SizedBox.shrink(key: ValueKey('logs-filtered-count-empty')),
                        ),
                        if (logs.filteredCount != entries.length)
                          KickBadge(
                            label: l10n.logsLoadedCount(entries.length),
                            leading: const Icon(KickIcons.expandMore),
                            emphasis: true,
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
                          selected: logs.selectedLevel == null,
                          onSelected: () {
                            unawaited(ref.read(logsControllerProvider.notifier).updateLevel(null));
                          },
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelInfo,
                          selected: logs.selectedLevel == AppLogLevel.info,
                          onSelected: () {
                            unawaited(
                              ref
                                  .read(logsControllerProvider.notifier)
                                  .updateLevel(AppLogLevel.info),
                            );
                          },
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelWarning,
                          selected: logs.selectedLevel == AppLogLevel.warning,
                          onSelected: () {
                            unawaited(
                              ref
                                  .read(logsControllerProvider.notifier)
                                  .updateLevel(AppLogLevel.warning),
                            );
                          },
                        ),
                        _LogsFilterChip(
                          label: l10n.logsLevelError,
                          selected: logs.selectedLevel == AppLogLevel.error,
                          onSelected: () {
                            unawaited(
                              ref
                                  .read(logsControllerProvider.notifier)
                                  .updateLevel(AppLogLevel.error),
                            );
                          },
                        ),
                      ],
                    ),
                    if (logs.categories.length > 1) ...[
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
                            selected: logs.selectedCategory == null,
                            onSelected: () {
                              unawaited(
                                ref.read(logsControllerProvider.notifier).updateCategory(null),
                              );
                            },
                          ),
                          ...logs.categories.map(
                            (category) => _LogsFilterChip(
                              label: category,
                              selected: logs.selectedCategory == category,
                              onSelected: () {
                                unawaited(
                                  ref
                                      .read(logsControllerProvider.notifier)
                                      .updateCategory(category),
                                );
                              },
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
            if (logs.filteredCount == 0)
              SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  child: EmptyStateCard(
                    icon: KickIcons.logs,
                    title: logs.totalCount == 0 ? l10n.logsEmptyTitle : l10n.logsFilteredEmptyTitle,
                    message: logs.totalCount == 0 ? null : l10n.logsFilteredEmptyMessage,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = displayItems[index];
                  return _LogCardReveal(
                    key: ValueKey('log-card-${item.key}'),
                    animate: item.entries.any((entry) => logs.appearingEntryIds.contains(entry.id)),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: index == displayItems.length - 1 ? 0 : 12),
                      child: switch (item) {
                        SingleLogDisplayItem(:final entry) => _LogCard(
                          entry: entry,
                          expandedPayload: _expandedPayloadEntries.contains(entry.id),
                          onCopy: () => _copyLogEntry(entry),
                          onTogglePayload: () => _togglePayload(entry.id),
                        ),
                        RequestLogDisplayItem() => _LogRequestGroupCard(
                          group: item,
                          expanded: _expandedRequestEntries.contains(item.requestId),
                          expandedPayloadEntryIds: _expandedPayloadEntries,
                          onToggleExpanded: () => _toggleRequestEntries(item.requestId),
                          onCopyEntry: _copyLogEntry,
                          onTogglePayload: _togglePayload,
                        ),
                        _ => const SizedBox.shrink(),
                      },
                    ),
                  );
                }, childCount: displayItems.length),
              ),
            if (logs.hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                  child: Center(
                    child: KickSecondaryAction(
                      onPressed: logs.isLoadingMore
                          ? null
                          : () => ref.read(logsControllerProvider.notifier).loadMore(),
                      busy: logs.isLoadingMore,
                      icon: KickIcons.expandMore,
                      label: l10n.logsLoadMoreButton,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppShell.floatingNavigationClearanceOf(context)),
            ),
          ],
        );
      },
      error: (error, stackTrace) => EmptyStateCard(
        icon: KickIcons.error,
        title: l10n.logsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: KickLoadingIndicator()),
    );
  }

  Future<void> _exportLogs() async {
    final l10n = context.l10n;
    final entries = await ref.read(logsControllerProvider.notifier).readAllMatchingEntries();
    if (entries.isEmpty) {
      _showSnackBar(l10n.logsNothingToExportMessage);
      return;
    }

    setState(() => _isExporting = true);
    try {
      final metadata = await _buildExportMetadata();
      final result = await ref
          .read(logExportServiceProvider)
          .export(entries, dialogTitle: l10n.logsExportDialogTitle, metadata: metadata);
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

  Future<void> _shareLogs() async {
    final l10n = context.l10n;
    final entries = await ref.read(logsControllerProvider.notifier).readAllMatchingEntries();
    if (entries.isEmpty) {
      _showSnackBar(l10n.logsNothingToExportMessage);
      return;
    }

    setState(() => _isSharing = true);
    try {
      final metadata = await _buildExportMetadata();
      await ref.read(logExportServiceProvider).share(entries, metadata: metadata);
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
          icon: const Icon(KickIcons.deleteSweep),
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
    _expandedRequestEntries.clear();
    await ref.read(logsControllerProvider.notifier).clear();
  }

  Future<void> _copyLogEntry(AppLogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: _formatLogEntryForClipboard(context.l10n, entry)));
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

  void _toggleRequestEntries(String requestId) {
    setState(() {
      if (_expandedRequestEntries.contains(requestId)) {
        _expandedRequestEntries.remove(requestId);
      } else {
        _expandedRequestEntries.add(requestId);
      }
    });
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<LogExportMetadata> _buildExportMetadata() async {
    final logs = ref.read(logsControllerProvider).asData?.value;
    final settings = ref.read(settingsControllerProvider).asData?.value;
    final locale = Localizations.localeOf(context).toLanguageTag();
    String? appVersion;
    try {
      appVersion = await ref.read(appVersionProvider.future);
    } catch (_) {
      appVersion = null;
    }

    return LogExportMetadata(
      appVersion: appVersion,
      locale: locale,
      query: logs?.query,
      level: logs?.selectedLevel,
      category: logs?.selectedCategory,
      retainedEntries: logs?.totalCount,
      matchingEntries: logs?.filteredCount,
      retentionLimit: settings?.logRetentionCount,
      loggingVerbosity: settings?.loggingVerbosity,
      unsafeRawLoggingEnabled: settings?.unsafeRawLoggingEnabled,
      requestMaxRetries: settings?.requestMaxRetries,
      retry429DelaySeconds: settings?.retry429DelaySeconds,
      mark429AsUnhealthy: settings?.mark429AsUnhealthy,
      androidBackgroundRuntime: settings?.androidBackgroundRuntime,
    );
  }
}

class _LogCardReveal extends StatefulWidget {
  const _LogCardReveal({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_LogCardReveal> createState() => _LogCardRevealState();
}

class _LogCardRevealState extends State<_LogCardReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.025),
    end: Offset.zero,
  ).animate(_curve);
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _hasAnimated = true;
      unawaited(_controller.forward());
    }
  }

  @override
  void didUpdateWidget(covariant _LogCardReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_hasAnimated) {
      _hasAnimated = true;
      unawaited(_controller.forward(from: 0));
    } else if (!widget.animate && !_hasAnimated) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

class _LogsFilterChip extends StatelessWidget {
  const _LogsFilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        KickHaptics.selection();
        onSelected();
      },
    );
  }
}

class _LogRequestGroupCard extends StatelessWidget {
  const _LogRequestGroupCard({
    required this.group,
    required this.expanded,
    required this.expandedPayloadEntryIds,
    required this.onToggleExpanded,
    required this.onCopyEntry,
    required this.onTogglePayload,
  });

  final RequestLogDisplayItem group;
  final bool expanded;
  final Set<String> expandedPayloadEntryIds;
  final VoidCallback onToggleExpanded;
  final ValueChanged<AppLogEntry> onCopyEntry;
  final ValueChanged<String> onTogglePayload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatter = DateFormat('dd.MM.yyyy HH:mm:ss', l10n.localeName);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.kickTokens;
    final primaryEntry = group.primaryEntry;
    final level = group.effectiveLevel;
    final levelColor = switch (level) {
      AppLogLevel.warning => scheme.tertiary,
      AppLogLevel.error => scheme.error,
      AppLogLevel.info => scheme.primary,
    };
    final model = group.model;
    final requestLabel = '#${group.requestNumber}';

    return KickPanel(
      tone: level == AppLogLevel.info ? KickPanelTone.soft : KickPanelTone.muted,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 92,
                decoration: BoxDecoration(
                  color: levelColor,
                  borderRadius: BorderRadius.circular(999),
                ),
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
                          label: l10n.logsRequestGroupTitle(requestLabel),
                          leading: const Icon(KickIcons.data),
                          emphasis: true,
                          tint: levelColor,
                        ),
                        KickBadge(
                          label: _logLevelLabel(l10n, level),
                          leading: Icon(_logLevelIcon(level), size: 16),
                          tint: levelColor,
                        ),
                        KickBadge(
                          label: primaryEntry.category,
                          leading: const Icon(KickIcons.label),
                        ),
                        Text(
                          formatter.format(primaryEntry.timestamp),
                          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      localizeLogMessage(l10n, LogSanitizer.sanitizeText(primaryEntry.message)),
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        KickBadge(
                          label: l10n.logsRequestStatusCount(group.entries.length),
                          leading: const Icon(KickIcons.logs),
                        ),
                        if (group.retryCount > 0)
                          KickBadge(
                            label: l10n.logsRequestRetryCount(group.retryCount),
                            leading: const Icon(KickIcons.restart),
                            emphasis: true,
                            tint: scheme.tertiary,
                          ),
                        KickBadge(
                          label: _shortRequestId(group.requestId),
                          leading: const Icon(KickIcons.badge),
                        ),
                        if (model != null)
                          KickBadge(label: model, leading: const Icon(KickIcons.hub)),
                      ],
                    ),
                    if (primaryEntry.route?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(
                        primaryEntry.route!,
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 12),
                    KickSecondaryAction(
                      onPressed: onToggleExpanded,
                      icon: expanded ? KickIcons.unfoldLess : KickIcons.expandMore,
                      label: expanded
                          ? l10n.logsRequestDetailsHideButton
                          : l10n.logsRequestDetailsShowButton,
                      variant: KickSecondaryActionVariant.text,
                    ),
                  ],
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: tokens.mediumDuration,
            switchInCurve: tokens.emphasizedCurve,
            switchOutCurve: tokens.standardCurve,
            child: expanded
                ? Padding(
                    key: ValueKey('request-details-${group.requestId}'),
                    padding: const EdgeInsets.only(top: 14),
                    child: _LogRequestTimeline(
                      entries: group.entries.reversed.toList(growable: false),
                      expandedPayloadEntryIds: expandedPayloadEntryIds,
                      onCopyEntry: onCopyEntry,
                      onTogglePayload: onTogglePayload,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('request-details-empty')),
          ),
        ],
      ),
    );
  }
}

class _LogRequestTimeline extends StatelessWidget {
  const _LogRequestTimeline({
    required this.entries,
    required this.expandedPayloadEntryIds,
    required this.onCopyEntry,
    required this.onTogglePayload,
  });

  final List<AppLogEntry> entries;
  final Set<String> expandedPayloadEntryIds;
  final ValueChanged<AppLogEntry> onCopyEntry;
  final ValueChanged<String> onTogglePayload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final indexed in entries.indexed) ...[
            _LogRequestTimelineEntry(
              index: indexed.$1 + 1,
              entry: indexed.$2,
              expandedPayload: expandedPayloadEntryIds.contains(indexed.$2.id),
              onCopy: () => onCopyEntry(indexed.$2),
              onTogglePayload: () => onTogglePayload(indexed.$2.id),
            ),
            if (indexed.$1 != entries.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _LogRequestTimelineEntry extends StatelessWidget {
  const _LogRequestTimelineEntry({
    required this.index,
    required this.entry,
    required this.expandedPayload,
    required this.onCopy,
    required this.onTogglePayload,
  });

  final int index;
  final AppLogEntry entry;
  final bool expandedPayload;
  final VoidCallback onCopy;
  final VoidCallback onTogglePayload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final formatter = DateFormat('HH:mm:ss', l10n.localeName);
    final sanitizedMessage = localizeLogMessage(l10n, LogSanitizer.sanitizeText(entry.message));
    final sanitizedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
    final levelColor = switch (entry.level) {
      AppLogLevel.warning => scheme.tertiary,
      AppLogLevel.error => scheme.error,
      AppLogLevel.info => scheme.primary,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              levelColor.withValues(alpha: 0.14),
              scheme.surfaceContainerHigh,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('$index', style: textTheme.labelMedium?.copyWith(color: levelColor)),
          ),
        ),
        const SizedBox(width: 12),
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
                    label: _logLevelLabel(l10n, entry.level),
                    leading: Icon(_logLevelIcon(entry.level), size: 16),
                    tint: levelColor,
                  ),
                  Text(
                    formatter.format(entry.timestamp),
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(sanitizedMessage, style: textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  KickSecondaryAction(
                    onPressed: onCopy,
                    icon: KickIcons.copyAll,
                    label: l10n.logsCopyEntryButton,
                    variant: KickSecondaryActionVariant.text,
                  ),
                  if (sanitizedPayload?.isNotEmpty == true)
                    KickSecondaryAction(
                      onPressed: onTogglePayload,
                      icon: expandedPayload ? KickIcons.unfoldLess : KickIcons.data,
                      label: expandedPayload
                          ? l10n.logsPayloadHideButton
                          : l10n.logsPayloadShowButton,
                      variant: KickSecondaryActionVariant.text,
                    ),
                ],
              ),
              if (expandedPayload && sanitizedPayload?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
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
    );
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
    final sanitizedMessage = localizeLogMessage(
      context.l10n,
      LogSanitizer.sanitizeText(entry.message),
    );
    final sanitizedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
    final levelColor = switch (entry.level) {
      AppLogLevel.warning => scheme.tertiary,
      AppLogLevel.error => scheme.error,
      AppLogLevel.info => scheme.primary,
    };

    return KickPanel(
      tone: entry.level == AppLogLevel.info ? KickPanelTone.soft : KickPanelTone.muted,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
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
                    KickBadge(label: entry.category, leading: const Icon(KickIcons.label)),
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
                    KickSecondaryAction(
                      onPressed: onCopy,
                      icon: KickIcons.copyAll,
                      label: context.l10n.logsCopyEntryButton,
                      variant: KickSecondaryActionVariant.text,
                    ),
                    if (sanitizedPayload?.isNotEmpty == true)
                      KickSecondaryAction(
                        onPressed: onTogglePayload,
                        icon: expandedPayload ? KickIcons.unfoldLess : KickIcons.data,
                        label: expandedPayload
                            ? context.l10n.logsPayloadHideButton
                            : context.l10n.logsPayloadShowButton,
                        variant: KickSecondaryActionVariant.text,
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

String _shortRequestId(String requestId) {
  final trimmed = requestId.trim();
  if (trimmed.length <= 12) {
    return trimmed;
  }
  return '${trimmed.substring(0, 8)}...';
}

IconData _logLevelIcon(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.info => KickIcons.info,
    AppLogLevel.warning => KickIcons.warning,
    AppLogLevel.error => KickIcons.error,
  };
}

String _formatLogEntryForClipboard(KickLocalizations l10n, AppLogEntry entry) {
  final sanitizedMessage = localizeLogMessage(l10n, LogSanitizer.sanitizeText(entry.message));
  final sanitizedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
  final buffer = StringBuffer()
    ..writeln('[${_logLevelLabel(l10n, entry.level)}] ${entry.category}')
    ..writeln('${l10n.logsExportTimestampLabel}: ${entry.timestamp.toIso8601String()}')
    ..writeln(sanitizedMessage);

  if (entry.route?.trim().isNotEmpty == true) {
    buffer.writeln('${l10n.logsExportRouteLabel}: ${entry.route}');
  }
  if (sanitizedPayload?.trim().isNotEmpty == true) {
    buffer
      ..writeln()
      ..writeln('${l10n.logsExportMaskedPayloadLabel}:')
      ..writeln(sanitizedPayload);
  }

  return buffer.toString().trimRight();
}
