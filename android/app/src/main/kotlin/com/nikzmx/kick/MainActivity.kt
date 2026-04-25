package com.nikzmx.kick

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val ANDROID_RUNTIME_CHANNEL = "kick/android_runtime"
        private const val APP_UPDATE_CHANNEL = "kick/app_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val ANDROID_17_API = 37
        private const val LOCAL_NETWORK_PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
        private const val LOCAL_NETWORK_PERMISSION_REQUEST_CODE = 7017
    }

    private val pendingLocalNetworkPermissionResults = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANDROID_RUNTIME_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "ensureLocalNetworkPermission" -> {
                        ensureLocalNetworkPermission(result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestPackageInstalls" -> {
                        result.success(canRequestPackageInstalls())
                    }
                    "openUnknownSourcesSettings" -> {
                        openUnknownSourcesSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")?.trim().orEmpty()
                        if (filePath.isEmpty()) {
                            result.error("invalid_args", "Missing APK file path.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(installApk(filePath))
                        } catch (error: SecurityException) {
                            result.error("permission_denied", error.message, null)
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCAL_NETWORK_PERMISSION_REQUEST_CODE) {
            return
        }

        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED ||
            hasLocalNetworkPermission()
        val results = pendingLocalNetworkPermissionResults.toList()
        pendingLocalNetworkPermissionResults.clear()
        results.forEach { it.success(granted) }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(POWER_SERVICE) as? PowerManager
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (isIgnoringBatteryOptimizations()) {
            return
        }

        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = "package:$packageName".toUri()
        }

        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun ensureLocalNetworkPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < ANDROID_17_API || hasLocalNetworkPermission()) {
            result.success(true)
            return
        }

        pendingLocalNetworkPermissionResults += result
        if (pendingLocalNetworkPermissionResults.size > 1) {
            return
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(LOCAL_NETWORK_PERMISSION),
            LOCAL_NETWORK_PERMISSION_REQUEST_CODE
        )
    }

    private fun hasLocalNetworkPermission(): Boolean {
        if (Build.VERSION.SDK_INT < ANDROID_17_API) {
            return true
        }

        return ContextCompat.checkSelfPermission(
            this,
            LOCAL_NETWORK_PERMISSION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }

        return packageManager.canRequestPackageInstalls()
    }

    private fun openUnknownSourcesSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = "package:$packageName".toUri()
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(
                Intent(Settings.ACTION_SECURITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
    }

    private fun installApk(filePath: String): Boolean {
        if (!canRequestPackageInstalls()) {
            throw SecurityException("Allow installs from this source before continuing.")
        }

        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw IllegalStateException("The downloaded APK was not found.")
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.kick_update_provider",
            apkFile
        )

        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = apkUri
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            startActivity(installIntent)
        } catch (_: ActivityNotFoundException) {
            startActivity(fallbackIntent)
        }

        return true
    }
}
