package com.dukaledger.duka_ledger

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
