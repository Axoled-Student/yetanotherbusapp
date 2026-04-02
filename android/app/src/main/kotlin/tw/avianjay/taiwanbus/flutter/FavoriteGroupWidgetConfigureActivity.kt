package tw.avianjay.taiwanbus.flutter

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle

class FavoriteGroupWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(
            RESULT_CANCELED,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val groups = FavoriteGroupWidgetSupport.loadFavoriteGroupNames(this)
        if (groups.isEmpty()) {
            AlertDialog.Builder(this)
                .setTitle("沒有可用的最愛類別")
                .setMessage("請先創建一個我的最愛類別。")
                .setPositiveButton(android.R.string.ok) { _, _ ->
                    finish()
                }
                .setOnCancelListener {
                    finish()
                }
                .show()
            return
        }

        AlertDialog.Builder(this)
            .setTitle("選擇一個我的最愛群組")
            .setItems(groups.toTypedArray()) { _, which ->
                completeConfiguration(groups[which])
            }
            .setOnCancelListener {
                finish()
            }
            .show()
    }

    private fun completeConfiguration(groupName: String) {
        FavoriteGroupWidgetSupport.saveConfiguredGroup(this, appWidgetId, groupName)
        FavoriteWidgetRefreshScheduler.syncFromPreferences(applicationContext)
        FavoriteGroupWidgetSupport.updateWidgetsAsync(
            context = applicationContext,
            appWidgetIds = intArrayOf(appWidgetId),
            showLoading = true,
        )
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }
}
