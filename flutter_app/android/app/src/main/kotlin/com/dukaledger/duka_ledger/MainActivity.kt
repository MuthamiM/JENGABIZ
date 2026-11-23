package com.dukaledger.duka_ledger

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dukaledger.duka_ledger/app_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val versionCode = if (Build.VERSION.SDK_INT >= 28) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionName" to (info.versionName ?: "Unknown"),
                                "versionCode" to versionCode,
                            ),
                        )
                    } catch (_: Exception) {
                        result.error(
                            "app_info_unavailable",
                            "Unable to read the installed app version.",
                            null,
                        )
                    }
                }

                "canInstallApk" -> {
                    result.success(
                        Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls(),
                    )
                }

                "openInstallSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error(
                            "install_settings_unavailable",
                            "Unable to open Android install settings.",
                            null,
                        )
                    }
                }

                "installApk" -> {
                    try {
                        val rawPath = call.argument<String>("path")
                            ?: throw IllegalArgumentException("Missing update file path.")
                        val apk = File(rawPath).canonicalFile
                        val cacheRoot =
                            File(cacheDir, "jengabiz_updates").canonicalPath + File.separator
                        if (!apk.path.startsWith(cacheRoot) ||
                            !apk.isFile ||
                            apk.extension.lowercase() != "apk"
                        ) {
                            throw IllegalArgumentException("Invalid update file.")
                        }
                        if (Build.VERSION.SDK_INT >= 26 &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            result.error(
                                "install_permission_required",
                                "Allow JengaBiz to install updates in Android settings.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apk,
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            clipData = ClipData.newUri(contentResolver, "JengaBiz update", uri)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error(
                            "apk_install_failed",
                            "Android could not open the verified update installer.",
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dukaledger.duka_ledger/widget",
        ).setMethodCallHandler { call, result ->
            if (call.method == "refresh") {
                try {
                    JengaBizStockWidgetProvider.refreshWidgets(applicationContext)
                    result.success(null)
                } catch (_: Exception) {
                    result.error(
                        "widget_refresh_failed",
                        "Unable to refresh the stock widget.",
                        null,
                    )
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
