import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

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
  bool _isExporting = false;
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsValue = ref.watch(logsControllerProvider);

    return logsValue.when(
      data: (logs) {
        final filtered = logs
            .where((entry) {
              final query = _query.trim().toLowerCase();
              if (query.isEmpty) {
                return true;
              }
              final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
              final sanitizedPayload =
                  LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload) ?? '';
              return sanitizedMessage.toLowerCase().contains(query) ||
                  (entry.route ?? '').toLowerCase().contains(query) ||
                  sanitizedPayload.toLowerCase().contains(query);
            })
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
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
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  IconButton(
                    onPressed: () => ref.read(logsControllerProvider.notifier).refreshState(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => ref.read(logsControllerProvider.notifier).clear(),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            KickPanel(
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
                        leading: const Icon(Icons.notes_rounded),
                      ),
                      KickBadge(
                        label: l10n.logsFilteredCount(filtered.length),
                        leading: const Icon(Icons.filter_alt_outlined),
                        emphasis: _query.trim().isNotEmpty,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              SizedBox(
                width: double.infinity,
                child: EmptyStateCard(icon: Icons.notes_rounded, title: l10n.logsEmptyTitle),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _LogCard(entry: filtered[index]),
                ),
              ),
          ],
        );
      },
      error: (error, stackTrace) => EmptyStateCard(
        icon: Icons.error_outline_rounded,
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
      final result = await ref.read(logExportServiceProvider).export(entries);
      if (!mounted) {
        return;
      }
      _showSnackBar(l10n.logsExportedMessage(p.basename(result.file.path)));
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

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final AppLogEntry entry;

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
                      label: entry.category,
                      leading: const Icon(Icons.bolt_outlined),
                      emphasis: true,
                      tint: levelColor,
                    ),
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
                if (sanitizedPayload?.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
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
