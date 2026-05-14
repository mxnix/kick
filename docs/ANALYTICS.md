# Analytics Events

KiCk reports anonymous, opt-in analytics through [Aptabase](https://aptabase.com). Reporting is **disabled by default** and only happens after a user opens the disclaimer and explicitly toggles analytics on. Disabling the toggle from settings emits a single `analytics_consent_revoked` marker, then purges the local outgoing queue.

This document is the source of truth for the event names and properties shipped today. If a property is missing from this list, it is not sent.

## Conventions

- `build_channel` is added automatically to every event (`release` or `debug`).
- Booleans are sent as native `true`/`false`.
- `model_family` is a non-identifying bucket derived through `KickAnalytics.modelFamily`. It never contains a raw model id.
- `provider` is `google` or `kiro` (matches `AccountProvider`).
- `session_id` ties together events that belong to the same proxy session, including the final `proxy_session_summary`.
- `schema_version` on `proxy_session_summary` (currently `2`) is bumped whenever fields are renamed or removed.
- Latency values are measured server-side in the proxy isolate and forwarded through the controller.

## Lifecycle

| Event | Description |
| --- | --- |
| `app_open` | Sent once per cold start after the warmup pipeline finishes. |
| `app_open_perf` | Bootstrap timings: `total_ms`, optional `proxy_ms`, `logs_scrub_ms`, plus `platform`. Bucketed to reduce cardinality. |
| `disclaimer_accepted` | Fired when the user finishes the first-run disclaimer. Includes `analytics_enabled`. |
| `analytics_consent_revoked` | Final marker emitted just before consent is turned off; the queue is purged afterwards. |

## Accounts

| Event | Description |
| --- | --- |
| `account_connect_started` | Includes `reauthorization`. |
| `account_connect_succeeded` | Includes `reauthorization`, `enabled_accounts`, `provider`. |
| `account_connect_failed` | Includes `reauthorization`, `error_kind`, `provider`. |
| `account_state_changed` | `action` is one of `enabled`, `disabled`, `removed`. Carries `provider`, `enabled_accounts`, `total_accounts`. |

## Proxy runtime

| Event | Description |
| --- | --- |
| `proxy_started` | `allow_lan`, `active_accounts`, `session_id`, optional `start_latency_ms`. |
| `proxy_start_failed` | `error_kind` plus `session_id` if known. |
| `first_successful_request` | Sent **once per process**: `route`, `model_family`, `stream`, `session_id`, `latency_ms`. |
| `proxy_request_failed` | Per-request error metadata: `route`, `model_family`, `stream`, `error_kind`, optional `error_source`, `status_code`, `error_detail`, `upstream_reason`, `retry_after_ms`, `has_action_url`, `session_id`, `latency_ms`. Capped per session. |
| `proxy_request_retried` | Adds `outcome`, `retry_count`, `upstream_retry_count`, `account_failover_count`, `retry_kinds`, `retry_delay_ms`. Capped per session. |
| `upstream_compatibility_issue` | Surfaces structurally meaningful upstream problems (`unsupported_model`, `project_id_missing`, etc.). |
| `proxy_session_summary` | One per session, with the schema described below. |

### `proxy_session_summary` schema (v2)

| Property | Notes |
| --- | --- |
| `schema_version` | `2`. |
| `session_id` | Same id used by request-level events. |
| `stop_reason` | `stopped`, `runtime_error`, `port_in_use`, etc. |
| `uptime_sec` | Wall-clock seconds since runtime first reported `running`. |
| `request_count`, `success_count`, `failed_count`, `retried_count` | Aggregate counters. |
| `failed_dropped`, `retried_dropped` | Number of per-session events suppressed by throttling. |
| `latency_p50_ms`, `latency_p95_ms`, `latency_max_ms` | Aggregated request latency. |
| `routes_seen` | Comma-joined list of distinct `/v1/...` paths used during the session. |
| `model_families_seen` | Comma-joined list of distinct `model_family` values. |
| `active_accounts`, `healthy_accounts` | Pool snapshot at the time the summary is emitted. |
| `request_max_retries`, `mark_429_as_unhealthy`, `android_background_runtime` | Runtime configuration. |

## Mobile lifecycle

| Event | Description |
| --- | --- |
| `android_background_session` | `duration_sec`, `killed_in_background`, `android_background_runtime_enabled`, `proxy_was_running`. |

## Updates

| Event | Description |
| --- | --- |
| `update_check_completed` | `has_update`, `installer_available`, `platform`, optional `error_kind`. |
| `update_download_completed` | `succeeded`, `checksum_verified`, `platform`, optional `size_mb`, `duration_ms`, `error_kind`. |
| `update_install_launched` | `permission_required`, `platform`. |
| `update_install_failed` | `error_kind`, `platform`. |

## Backups & integrations

| Event | Description |
| --- | --- |
| `backup_exported` | `encrypted`, `account_count`, `accounts_with_tokens`. |
| `backup_restored` | `encrypted`, `account_count`, `accounts_without_tokens`, optional `error_kind`. |
| `silly_tavern_push_succeeded` | (no extra properties). |
| `silly_tavern_push_failed` | `failure_kind`, optional `status_code`. |
| `logs_exported` | `target` (`save` or `share`), `entry_count`. |

## What is **not** sent

- Prompt or response text.
- API keys, OAuth tokens, or session secrets.
- Email addresses or `PROJECT_ID`.
- Raw or sanitized log payloads.
- Custom model identifiers (only `model_family` buckets).
