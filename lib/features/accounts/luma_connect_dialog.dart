import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kick_icons.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/luma/luma_connect_service.dart';
import '../shared/kick_actions.dart';

/// Result returned by [showLumaConnectDialog].
class LumaConnectDialogResult {
  const LumaConnectDialogResult({required this.connect});

  final LumaConnectResult connect;
}

/// Opens the Luma sign-in dialog backed by the paste-cookie flow.
///
/// Returns the resolved session bundle on success, or `null` when the user
/// cancels.
Future<LumaConnectDialogResult?> showLumaConnectDialog(
  BuildContext context, {
  required LumaConnectService service,
  required String tokenRef,
  String? labelHint,
}) {
  return showDialog<LumaConnectDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _LumaConnectDialog(service: service, tokenRef: tokenRef, labelHint: labelHint),
  );
}

class _LumaConnectDialog extends StatefulWidget {
  const _LumaConnectDialog({required this.service, required this.tokenRef, this.labelHint});

  final LumaConnectService service;
  final String tokenRef;
  final String? labelHint;

  @override
  State<_LumaConnectDialog> createState() => _LumaConnectDialogState();
}

class _LumaConnectDialogState extends State<_LumaConnectDialog> {
  late final TextEditingController _cookieController;
  late final TextEditingController _labelController;
  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _cookieController = TextEditingController();
    _labelController = TextEditingController(text: widget.labelHint ?? '');
  }

  @override
  void dispose() {
    _cookieController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _cookieController.text;
    if (raw.trim().isEmpty) {
      setState(() => _errorText = context.l10n.lumaConnectCookieMissingError);
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final result = await widget.service.connectWithRawCookies(
        tokenRef: widget.tokenRef,
        rawCookieHeader: raw,
        labelOverride: _labelController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(LumaConnectDialogResult(connect: result));
    } on LumaConnectException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _localizeError(context.l10n, error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = context.l10n.lumaConnectUnknownError;
      });
    }
  }

  Future<void> _openLumaInBrowser() async {
    final uri = Uri.parse('https://app.lumalabs.ai/');
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted || opened) return;
      messenger?.showSnackBar(SnackBar(content: Text(context.l10n.lumaConnectOpenBrowserFailed)));
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(context.l10n.lumaConnectOpenBrowserFailed)));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.l10n.lumaConnectClipboardEmpty)));
      return;
    }
    setState(() {
      _cookieController.text = text.trim();
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: const Icon(KickIcons.security),
      title: Text(l10n.lumaConnectDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.lumaConnectDialogIntro,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.lumaConnectStepsTitle, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      l10n.lumaConnectStepsBody,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _openLumaInBrowser,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(l10n.lumaConnectOpenBrowserButton),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _cookieController,
                enabled: !_busy,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.lumaConnectCookieFieldLabel,
                  helperText: l10n.lumaConnectCookieFieldHelper,
                  helperMaxLines: 3,
                  alignLabelWithHint: true,
                  errorText: _errorText,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _pasteFromClipboard,
                  icon: const Icon(KickIcons.copy, size: 18),
                  label: Text(l10n.lumaConnectPasteFromClipboardButton),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _labelController,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.accountNameLabel,
                  hintText: l10n.accountNameHint,
                  helperText: l10n.accountNameHelperText,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: KickLoadingIndicator(size: 18, contained: false),
                )
              : const Icon(KickIcons.check, size: 18),
          label: Text(l10n.lumaConnectSubmitButton),
        ),
      ],
    );
  }
}

String _localizeError(KickLocalizations l10n, LumaConnectErrorCode code) {
  return switch (code) {
    LumaConnectErrorCode.invalidCookieHeader => l10n.lumaConnectInvalidCookieError,
    LumaConnectErrorCode.missingRequiredCookie => l10n.lumaConnectCookieMissingError,
    LumaConnectErrorCode.unauthorized => l10n.lumaConnectUnauthorizedError,
    LumaConnectErrorCode.networkFailure => l10n.lumaConnectNetworkFailureError,
    LumaConnectErrorCode.noTeamsAvailable => l10n.lumaConnectNoTeamsError,
    LumaConnectErrorCode.unknown => l10n.lumaConnectUnknownError,
  };
}
