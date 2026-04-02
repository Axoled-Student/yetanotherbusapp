package tw.avianjay.taiwanbus.flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var appLaunchChannel: MethodChannel? = null
    private var pendingLaunchPayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingLaunchPayload = AppLaunchConstants.extractLaunchPayload(intent)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    result.success(canRequestPackageInstalls())
                }

                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }

                "installApk" -> {
                    handleInstallApk(call, result)
                }

                else -> result.notImplemented()
            }
        }

        appLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LAUNCH_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitialLaunchAction" -> {
                        result.success(pendingLaunchPayload)
                        pendingLaunchPayload = null
                    }

                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_INTEGRATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pinStopShortcut" -> {
                    result.success(requestPinnedStopShortcut(call))
                }

                "refreshFavoriteWidgets" -> {
                    FavoriteGroupWidgetSupport.requestRefreshAll(this)
                    result.success(null)
                }

                "setFavoriteWidgetAutoRefreshMinutes" -> {
                    val minutes = call.argument<Int>("minutes") ?: 0
                    FavoriteWidgetRefreshScheduler.sync(this, minutes)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = AppLaunchConstants.extractLaunchPayload(intent) ?: return
        pendingLaunchPayload = payload
        appLaunchChannel?.invokeMethod("onLaunchAction", payload)
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun handleInstallApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("missing_path", "APK path is required.", null)
            return
        }

        val apkFile = File(path)
        if (!apkFile.exists()) {
            result.error("missing_file", "APK file does not exist.", path)
            return
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile,
        )
        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = apkUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivity(installIntent)
        result.success(null)
    }

    private fun requestPinnedStopShortcut(call: MethodCall): Boolean {
        val provider = call.argument<String>("provider")?.trim().orEmpty()
        val routeKey = call.argument<Int>("routeKey")
        val pathId = call.argument<Int>("pathId")
        val stopId = call.argument<Int>("stopId")
        if (provider.isEmpty() || routeKey == null || pathId == null || stopId == null) {
            return false
        }

        val routeName = call.argument<String>("routeName")?.trim().orEmpty()
        val stopName = call.argument<String>("stopName")?.trim().orEmpty()
        val shortcutId = "stop_${provider}_${routeKey}_${pathId}_${stopId}"
        val shortLabel = when {
            stopName.isNotBlank() -> stopName
            routeName.isNotBlank() -> routeName
            else -> "YABus"
        }
        val longLabel = buildString {
            append(if (routeName.isNotBlank()) routeName else "Route $routeKey")
            if (stopName.isNotBlank()) {
                append(" - ")
                append(stopName)
            }
        }
        val intent = AppLaunchConstants.createRouteDetailIntent(
            context = this,
            provider = provider,
            routeKey = routeKey,
            pathId = pathId,
            stopId = stopId,
        ).apply {
            action = Intent.ACTION_VIEW
        }
        val shortcut = ShortcutInfoCompat.Builder(this, shortcutId)
            .setShortLabel(shortLabel.take(45))
            .setLongLabel(longLabel.take(100))
            .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(intent)
            .build()

        return ShortcutManagerCompat.requestPinShortcut(this, shortcut, null)
    }

    companion object {
        private const val UPDATE_INSTALLER_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/update_installer"
        private const val APP_LAUNCH_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/app_launch"
        private const val HOME_INTEGRATION_CHANNEL =
            "tw.avianjay.taiwanbus.flutter/home_integration"
    }
}
