package com.dukaledger.duka_ledger

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject

class JengaBizStockWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun refreshWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val provider = ComponentName(context, JengaBizStockWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(provider)
            updateWidgets(context, manager, widgetIds)
        }

        private fun updateWidgets(
            context: Context,
            manager: AppWidgetManager,
            widgetIds: IntArray,
        ) {
            val preferences = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
            val summary = runCatching {
                JSONObject(
                    preferences.getString("flutter.jengabiz_widget_summary", "{}")
                )
            }.getOrDefault(JSONObject())

            widgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.jengabiz_stock_widget).apply {
                    setTextViewText(R.id.widget_shop_name, summary.optString("shopName", "Your shop"))
                    setTextViewText(R.id.widget_item_count, summary.optInt("itemCount", 0).toString())
                    setTextViewText(R.id.widget_units_in_stock, summary.optInt("unitsInStock", 0).toString())
                    setTextViewText(R.id.widget_low_stock_count, summary.optInt("lowStockCount", 0).toString())
                }

                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    widgetId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                manager.updateAppWidget(widgetId, views)
            }
        }
    }
}
