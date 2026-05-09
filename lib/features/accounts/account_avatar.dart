import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/account_profile.dart';

class AccountAvatarImage extends StatelessWidget {
  const AccountAvatarImage({
    super.key,
    required this.account,
    required this.size,
    required this.radius,
  });

  final AccountProfile account;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = effectiveAccountAvatarUrl(account);
    final fallback = AccountAvatarFallback(account: account, size: size, radius: radius);

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return fallback;
    }

    final image = isFileAccountAvatarUrl(avatarUrl)
        ? Image.file(
            File.fromUri(Uri.parse(avatarUrl)),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}

class AccountAvatarFallback extends StatelessWidget {
  const AccountAvatarFallback({
    super.key,
    required this.account,
    required this.size,
    required this.radius,
  });

  final AccountProfile account;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = accountAvatarInitial(account);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: initial == null
            ? Icon(
                Icons.account_circle_rounded,
                color: scheme.onSecondaryContainer,
                size: size * 0.58,
              )
            : Text(
                initial,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

String? effectiveAccountAvatarUrl(AccountProfile account) {
  final stored = account.avatarUrl?.trim();
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }
  if (account.provider == AccountProvider.kiro) {
    return diceBearAccountAvatarUrl(account.id);
  }
  return null;
}

String diceBearAccountAvatarUrl(String seed) {
  return Uri.https('api.dicebear.com', '/9.x/identicon/png', {
    'seed': seed.trim().isEmpty ? 'kick' : seed.trim(),
    'radius': '28',
    'backgroundType': 'solid',
  }).toString();
}

bool isFileAccountAvatarUrl(String value) {
  return value.startsWith('file://');
}

String? accountAvatarInitial(AccountProfile account) {
  final text = (account.label.trim().isNotEmpty ? account.label : account.displayIdentity).trim();
  if (text.isEmpty) {
    return null;
  }
  return String.fromCharCode(text.runes.first).toUpperCase();
}
