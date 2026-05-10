import '../../data/models/account_profile.dart';
import '../account_pool/account_pool.dart';
import '../gemini/gemini_usage_models.dart';
import 'kiro_auth_source.dart';
import 'kiro_code_assist_client.dart';

class KiroUsageService {
  KiroUsageService({KiroCodeAssistClient? client}) : _client = client ?? KiroCodeAssistClient();

  final KiroCodeAssistClient _client;

  Future<GeminiUsageSnapshot> fetchUsage(AccountProfile account) async {
    final source = await loadEffectiveKiroAuthSource(sourcePath: account.credentialSourcePath);
    if (source == null) {
      throw StateError('Kiro credentials for this account were not found.');
    }

    final rawUsage = await _client.getUsageLimits(
      account: ProxyRuntimeAccount(
        id: account.id,
        label: account.label,
        email: account.email.trim().isNotEmpty ? account.email : source.displayIdentity,
        projectId: account.projectId,
        provider: AccountProvider.kiro,
        providerRegion: source.effectiveRegion,
        credentialSourceType: source.sourceType,
        credentialSourcePath: source.sourcePath,
        providerProfileArn: resolveKiroProfileArn(
          source.profileArn,
          fallback: account.providerProfileArn,
        ),
        googleSubjectId: account.googleSubjectId,
        avatarUrl: account.avatarUrl,
        enabled: account.enabled,
        priority: account.priority,
        notSupportedModels: account.notSupportedModels,
        lastUsedAt: account.lastUsedAt,
        usageCount: account.usageCount,
        errorCount: account.errorCount,
        cooldownUntil: account.cooldownUntil,
        lastQuotaSnapshot: account.lastQuotaSnapshot,
        tokenRef: account.tokenRef,
        tokens: source.toOAuthTokens(),
      ),
    );

    return GeminiUsageSnapshot.fromKiroApi(rawUsage, fetchedAt: DateTime.now());
  }

  void dispose() {
    _client.dispose();
  }
}
