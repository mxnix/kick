import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/theme/kick_icons.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/luma/luma_connect_service.dart';
import '../../proxy/luma/luma_session.dart';
import '../shared/kick_actions.dart';
import 'luma_connect_dialog.dart';

const String _lumaLoginEntryUrl = 'https://app.lumalabs.ai/';

/// Returns `true` when the current platform has a working `flutter_inappwebview`
/// backend that can drive the auto-login flow. We deliberately disable it on
/// Linux because the upstream Linux backend uses WebKit2GTK, which Google's
/// embedded-user-agent guard blocks for Sign-in with Google.
bool isLumaWebViewLoginSupported() {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isWindows;
}

/// Opens the Luma sign-in webview. Returns a [LumaConnectDialogResult] on
/// success, the [LumaWebViewLoginManualFallback] sentinel when the user asks
/// to switch to manual paste, or `null` when the dialog is dismissed.
Future<Object?> showLumaWebViewLoginDialog(
  BuildContext context, {
  required LumaConnectService service,
  required String tokenRef,
  String? labelHint,
}) {
  return showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _LumaWebViewLoginDialog(service: service, tokenRef: tokenRef, labelHint: labelHint),
  );
}

/// Sentinel returned from [showLumaWebViewLoginDialog] when the user asks to
/// fall back to the paste-cookie dialog.
class LumaWebViewLoginManualFallback {
  const LumaWebViewLoginManualFallback();
}

class _LumaWebViewLoginDialog extends StatefulWidget {
  const _LumaWebViewLoginDialog({required this.service, required this.tokenRef, this.labelHint});

  final LumaConnectService service;
  final String tokenRef;
  final String? labelHint;

  @override
  State<_LumaWebViewLoginDialog> createState() => _LumaWebViewLoginDialogState();
}

class _LumaWebViewLoginDialogState extends State<_LumaWebViewLoginDialog> {
  // Modern Chrome desktop UA. Google rejects the default `wv` user-agent for
  // OAuth, so we masquerade as a real browser. This still lets Luma's BFF
  // identify us through cookies; the UA is only used by IdP heuristics.
  static const String _desktopChromeUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
  static const String _androidChromeUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.022) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36';

  InAppWebViewController? _controller;
  bool _busy = false;
  bool _capturing = false;
  String? _errorText;
  String? _currentUrl;

  String get _userAgent => Platform.isAndroid ? _androidChromeUa : _desktopChromeUa;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final maxWidth = (mediaSize.width - 48).clamp(320.0, 980.0);
    final maxHeight = (mediaSize.height - 96).clamp(420.0, 760.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(
              title: l10n.lumaConnectWebViewTitle,
              subtitle: l10n.lumaConnectWebViewSubtitle,
              onClose: _busy ? null : () => Navigator.of(context).pop(),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_rounded, size: 18, color: scheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri(_lumaLoginEntryUrl)),
                        initialSettings: InAppWebViewSettings(
                          userAgent: _userAgent,
                          javaScriptEnabled: true,
                          isInspectable: kDebugMode,
                          incognito: false,
                          useShouldOverrideUrlLoading: false,
                          thirdPartyCookiesEnabled: true,
                          // Required for Google sign-in popup screens, which
                          // some IdP flows (MFA, captcha) rely on.
                          supportMultipleWindows: false,
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
                        },
                        onLoadStop: (controller, url) async {
                          if (!mounted) return;
                          setState(() => _currentUrl = url?.toString());
                          await _maybeCaptureSession(url);
                        },
                        onReceivedError: (controller, request, error) {
                          if (!mounted) return;
                          // Filter out subresource errors (favicons, ads, etc.).
                          if (request.isForMainFrame == true) {
                            setState(() {
                              _errorText = '${error.type}: ${error.description}';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (_busy || _capturing)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.surface.withValues(alpha: 0.55),
                        child: const Center(child: KickLoadingIndicator(size: 32)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                _currentUrl == null
                    ? l10n.lumaConnectWebViewIdleHint
                    : l10n.lumaConnectWebViewLocationHint(_shortUrl(_currentUrl!)),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _resetSession,
                        icon: const Icon(KickIcons.deleteSweep, size: 18),
                        label: Text(l10n.lumaConnectWebViewClearSessionButton),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _switchToManualPaste,
                        icon: const Icon(KickIcons.copy, size: 18),
                        label: Text(l10n.lumaConnectWebViewManualFallbackButton),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
                        child: Text(l10n.cancelButton),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || _capturing ? null : _retryCapture,
                        icon: _capturing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: KickLoadingIndicator(size: 18, contained: false),
                              )
                            : const Icon(KickIcons.check, size: 18),
                        label: Text(l10n.lumaConnectWebViewSubmitButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _maybeCaptureSession(WebUri? url) async {
    if (!mounted || url == null) return;
    final host = url.host;
    final path = url.path;
    if (host != lumaPrimaryHost) return;
    // Skip the auth callback bounce - we want the next, post-redirect load.
    if (path.startsWith('/auth/callback')) return;
    if (_capturing || _busy) return;

    final cookieHeader = await _readLumaCookieHeader();
    if (!cookieHeader.contains('wos-session=')) {
      // Not yet logged in - keep waiting silently.
      return;
    }
    await _connectWithCookies(cookieHeader);
  }

  Future<void> _retryCapture() async {
    if (!mounted) return;
    setState(() {
      _capturing = true;
      _errorText = null;
    });
    try {
      final cookieHeader = await _readLumaCookieHeader();
      if (!cookieHeader.contains('wos-session=')) {
        if (!mounted) return;
        setState(() {
          _capturing = false;
          _errorText = context.l10n.lumaConnectWebViewNoSessionYetHint;
        });
        return;
      }
      await _connectWithCookies(cookieHeader);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _errorText = '$error';
      });
    }
  }

  Future<String> _readLumaCookieHeader() async {
    final manager = CookieManager.instance();
    final cookies = await manager.getCookies(url: WebUri('https://$lumaPrimaryHost/'));
    final pieces = <String>[];
    for (final cookie in cookies) {
      final name = cookie.name;
      if (!lumaSessionCookieNames.contains(name)) continue;
      final raw = cookie.value;
      final value = raw is String ? raw : raw.toString();
      if (value.isEmpty) continue;
      pieces.add('$name=$value');
    }
    return pieces.join('; ');
  }

  Future<void> _connectWithCookies(String cookieHeader) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _capturing = false;
      _errorText = null;
    });
    try {
      final result = await widget.service.connectWithRawCookies(
        tokenRef: widget.tokenRef,
        rawCookieHeader: cookieHeader,
        labelOverride: widget.labelHint,
      );
      if (!mounted) return;
      Navigator.of(context).pop(LumaConnectDialogResult(connect: result));
    } on LumaConnectException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = _localizeError(context.l10n, error.code);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = '$error';
      });
    }
  }

  Future<void> _resetSession() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final manager = CookieManager.instance();
      await manager.deleteAllCookies();
      await InAppWebViewController.clearAllCache();
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_lumaLoginEntryUrl)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _switchToManualPaste() async {
    Navigator.of(context).pop(const LumaWebViewLoginManualFallback());
  }

  String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final base = '${uri.scheme}://${uri.host}${uri.path}';
    return base.length > 96 ? '${base.substring(0, 93)}…' : base;
  }
}

/// Launches the best available Luma sign-in flow for the current platform:
/// the embedded webview on Android/Windows, or the paste-cookie dialog on
/// platforms without a usable webview backend.
///
/// Returns the resolved [LumaConnectDialogResult] or `null` if the user
/// cancels.
Future<LumaConnectDialogResult?> showLumaConnectFlow(
  BuildContext context, {
  required LumaConnectService service,
  required String tokenRef,
  String? labelHint,
}) async {
  if (!isLumaWebViewLoginSupported()) {
    return showLumaConnectDialog(
      context,
      service: service,
      tokenRef: tokenRef,
      labelHint: labelHint,
    );
  }

  final result = await showLumaWebViewLoginDialog(
    context,
    service: service,
    tokenRef: tokenRef,
    labelHint: labelHint,
  );
  if (result is LumaWebViewLoginManualFallback) {
    if (!context.mounted) return null;
    return showLumaConnectDialog(
      context,
      service: service,
      tokenRef: tokenRef,
      labelHint: labelHint,
    );
  }
  if (result is LumaConnectDialogResult) {
    return result;
  }
  return null;
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.subtitle, this.onClose});

  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(KickIcons.clear),
          ),
        ],
      ),
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
