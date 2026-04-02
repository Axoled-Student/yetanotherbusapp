package tw.avianjay.taiwanbus.flutter

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class FavoriteWidgetRefreshWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result {
        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
        val widgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(applicationContext, FavoriteGroupWidgetProvider::class.java),
        )
        if (widgetIds.isEmpty()) {
            return Result.success()
        }

        return try {
            FavoriteGroupWidgetSupport.updateWidgetsNow(
                context = applicationContext,
                appWidgetIds = widgetIds,
            )
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }
}
