package tw.avianjay.taiwanbus.flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.zip.InflaterInputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.json.JSONArray
import org.json.JSONObject
import org.w3c.dom.Element

class FavoriteGroupWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        FavoriteGroupWidgetSupport.updateWidgetsAsync(context, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != FavoriteGroupWidgetSupport.ACTION_REFRESH_WIDGET) {
            return
        }

        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return
        }

        val pendingResult = goAsync()
        FavoriteGroupWidgetSupport.updateWidgetsAsync(
            context = context,
            appWidgetIds = intArrayOf(appWidgetId),
            showLoading = true,
            pendingResult = pendingResult,
        )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { appWidgetId ->
            FavoriteGroupWidgetSupport.deleteConfiguredGroup(context, appWidgetId)
        }
    }
}

object FavoriteGroupWidgetSupport {
    const val ACTION_REFRESH_WIDGET =
        "tw.avianjay.taiwanbus.flutter.action.REFRESH_FAVORITE_WIDGET"

    private const val WIDGET_PREFERENCES_NAME = "favorite_group_widget"
    private const val WIDGET_GROUP_KEY_PREFIX = "group_"
    private const val FLUTTER_PREFERENCES_NAME = "FlutterSharedPreferences"
    private const val FAVORITE_GROUPS_KEY = "flutter.favorite_groups"
    private const val FAVORITE_GROUPS_FALLBACK_KEY = "favorite_groups"
    private const val MAX_WIDGET_ITEMS = 6

    private val executor = Executors.newSingleThreadExecutor()

    fun saveConfiguredGroup(context: Context, appWidgetId: Int, groupName: String) {
        widgetPreferences(context)
            .edit()
            .putString(widgetGroupKey(appWidgetId), groupName)
            .apply()
    }

    fun loadConfiguredGroup(context: Context, appWidgetId: Int): String? {
        return widgetPreferences(context).getString(widgetGroupKey(appWidgetId), null)
    }

    fun deleteConfiguredGroup(context: Context, appWidgetId: Int) {
        widgetPreferences(context).edit().remove(widgetGroupKey(appWidgetId)).apply()
    }

    fun loadFavoriteGroupNames(context: Context): List<String> {
        return loadFavoriteGroups(context).keys.sorted()
    }

    fun requestRefreshAll(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, FavoriteGroupWidgetProvider::class.java),
        )
        if (appWidgetIds.isNotEmpty()) {
            updateWidgetsAsync(context, appWidgetIds, showLoading = true)
        }
    }

    fun updateWidgetsAsync(
        context: Context,
        appWidgetIds: IntArray,
        showLoading: Boolean = false,
        pendingResult: BroadcastReceiver.PendingResult? = null,
    ) {
        val appContext = context.applicationContext
        val appWidgetManager = AppWidgetManager.getInstance(appContext)
        if (showLoading) {
            appWidgetIds.forEach { appWidgetId ->
                appWidgetManager.updateAppWidget(
                    appWidgetId,
                    buildLoadingRemoteViews(appContext, appWidgetId),
                )
            }
        }

        executor.execute {
            try {
                appWidgetIds.forEach { appWidgetId ->
                    updateWidget(appContext, appWidgetManager, appWidgetId)
                }
            } finally {
                pendingResult?.finish()
            }
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val groupName = loadConfiguredGroup(context, appWidgetId)
        val views = when {
            groupName.isNullOrBlank() -> {
                buildBaseRemoteViews(context, appWidgetId, "YABus").apply {
                    setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
                    setTextViewText(R.id.favorite_widget_empty, "Tap to configure this widget.")
                }
            }

            else -> {
                val items = loadFavoriteGroups(context)[groupName]
                if (items == null) {
                    buildBaseRemoteViews(context, appWidgetId, groupName).apply {
                        setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
                        setTextViewText(
                            R.id.favorite_widget_empty,
                            "This favorite group no longer exists.",
                        )
                    }
                } else {
                    buildContentRemoteViews(context, appWidgetId, groupName, items)
                }
            }
        }
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun buildLoadingRemoteViews(context: Context, appWidgetId: Int): RemoteViews {
        val title = loadConfiguredGroup(context, appWidgetId) ?: "YABus"
        return buildBaseRemoteViews(context, appWidgetId, title).apply {
            setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
            setTextViewText(R.id.favorite_widget_empty, "Updating...")
        }
    }

    private fun buildContentRemoteViews(
        context: Context,
        appWidgetId: Int,
        groupName: String,
        items: List<FavoriteWidgetItem>,
    ): RemoteViews {
        val views = buildBaseRemoteViews(context, appWidgetId, groupName)
        if (items.isEmpty()) {
            views.setViewVisibility(R.id.favorite_widget_empty, View.VISIBLE)
            views.setTextViewText(R.id.favorite_widget_empty, "空空如也")
            return views
        }

        val liveStopsByRoute = linkedMapOf<String, Map<Int, WidgetLiveStop>>()
        items.associateBy(::routeRequestKey).forEach { (requestKey, item) ->
            liveStopsByRoute[requestKey] = fetchLiveStopMap(item.routeKey)
        }

        views.removeAllViews(R.id.favorite_widget_items_container)
        items.take(MAX_WIDGET_ITEMS).forEach { item ->
            val liveStop = liveStopsByRoute[routeRequestKey(item)]?.get(item.stopId)
            val itemViews = RemoteViews(context.packageName, R.layout.favorite_group_widget_item)
            itemViews.setTextViewText(
                R.id.favorite_widget_item_eta,
                formatEtaText(liveStop),
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_route,
                item.routeName.ifBlank { "路線 ${item.routeKey}" },
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_stop,
                item.stopName.ifBlank { "站牌 ${item.stopId}" },
            )
            itemViews.setTextViewText(
                R.id.favorite_widget_item_note,
                liveStop?.vehicleId ?: item.provider.uppercase(),
            )
            itemViews.setOnClickPendingIntent(
                R.id.favorite_widget_item_root,
                createRoutePendingIntent(context, item),
            )
            views.addView(R.id.favorite_widget_items_container, itemViews)
        }

        return views
    }

    private fun buildBaseRemoteViews(
        context: Context,
        appWidgetId: Int,
        title: String,
    ): RemoteViews {
        return RemoteViews(context.packageName, R.layout.favorite_group_widget).apply {
            setTextViewText(R.id.favorite_widget_title, title)
            setOnClickPendingIntent(
                R.id.favorite_widget_header,
                createOpenFavoritesPendingIntent(context, appWidgetId, title),
            )
            setOnClickPendingIntent(
                R.id.favorite_widget_refresh,
                createRefreshPendingIntent(context, appWidgetId),
            )
            removeAllViews(R.id.favorite_widget_items_container)
            setViewVisibility(R.id.favorite_widget_empty, View.GONE)
        }
    }

    private fun createRefreshPendingIntent(
        context: Context,
        appWidgetId: Int,
    ): PendingIntent {
        val intent = Intent(context, FavoriteGroupWidgetProvider::class.java).apply {
            action = ACTION_REFRESH_WIDGET
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse("yabus://widget/$appWidgetId/refresh")
        }
        return PendingIntent.getBroadcast(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createOpenFavoritesPendingIntent(
        context: Context,
        appWidgetId: Int,
        groupName: String,
    ): PendingIntent {
        val intent = AppLaunchConstants.createFavoritesGroupIntent(context, groupName).apply {
            data = Uri.parse("yabus://widget/$appWidgetId/group/${Uri.encode(groupName)}")
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId * 17,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createRoutePendingIntent(
        context: Context,
        item: FavoriteWidgetItem,
    ): PendingIntent {
        val requestCode = (item.routeKey * 31) + item.stopId
        val intent = AppLaunchConstants.createRouteDetailIntent(
            context = context,
            provider = item.provider,
            routeKey = item.routeKey,
            pathId = item.pathId,
            stopId = item.stopId,
        ).apply {
            data = Uri.parse(
                "yabus://route/${item.provider}/${item.routeKey}/${item.pathId}/${item.stopId}",
            )
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun loadFavoriteGroups(context: Context): Map<String, List<FavoriteWidgetItem>> {
        val preferences = context.getSharedPreferences(
            FLUTTER_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(FAVORITE_GROUPS_KEY, null)
            ?: preferences.getString(FAVORITE_GROUPS_FALLBACK_KEY, null)
            ?: return emptyMap()
        val root = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return emptyMap()
        }

        val result = linkedMapOf<String, List<FavoriteWidgetItem>>()
        root.keys().forEach { groupName ->
            val groupItems = mutableListOf<FavoriteWidgetItem>()
            val groupArray = root.optJSONArray(groupName) ?: JSONArray()
            for (index in 0 until groupArray.length()) {
                val item = groupArray.optJSONObject(index) ?: continue
                val routeKey = item.optInt("routeKey", 0)
                val stopId = item.optInt("stopId", 0)
                if (routeKey <= 0 || stopId <= 0) {
                    continue
                }
                groupItems += FavoriteWidgetItem(
                    provider = item.optString("provider", "twn"),
                    routeKey = routeKey,
                    pathId = item.optInt("pathId", 0),
                    stopId = stopId,
                    routeName = item.optString("routeName", ""),
                    stopName = item.optString("stopName", ""),
                )
            }
            result[groupName] = groupItems
        }
        return result
    }

    private fun fetchLiveStopMap(routeKey: Int): Map<Int, WidgetLiveStop> {
        val connection = URL("https://busserver.bus.yahoo.com/api/route/$routeKey")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.doInput = true
        connection.useCaches = false

        return try {
            if (connection.responseCode !in 200..299) {
                return emptyMap()
            }
            val xmlText = decodeZlib(connection.inputStream)
            parseLiveStopMap(xmlText)
        } catch (_: Exception) {
            emptyMap()
        } finally {
            connection.disconnect()
        }
    }

    private fun decodeZlib(inputStream: InputStream): String {
        val bytes = inputStream.readBytes()
        return InflaterInputStream(ByteArrayInputStream(bytes))
            .bufferedReader(Charsets.UTF_8)
            .use { reader ->
                reader.readText()
            }
    }

    private fun parseLiveStopMap(xmlText: String): Map<Int, WidgetLiveStop> {
        val builder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        val document = builder.parse(xmlText.byteInputStream(Charsets.UTF_8))
        val elements = document.getElementsByTagName("e")
        val result = mutableMapOf<Int, WidgetLiveStop>()
        for (index in 0 until elements.length) {
            val element = elements.item(index) as? Element ?: continue
            val stopId = element.getAttribute("id").toIntOrNull() ?: continue
            val busElements = element.getElementsByTagName("b")
            val vehicleId = if (busElements.length > 0) {
                (busElements.item(0) as? Element)?.getAttribute("id")
            } else {
                null
            }
            result[stopId] = WidgetLiveStop(
                sec = element.getAttribute("sec").toIntOrNull(),
                msg = element.getAttribute("msg").takeIf { it.isNotBlank() },
                vehicleId = vehicleId?.takeIf { it.isNotBlank() },
            )
        }
        return result
    }

    private fun formatEtaText(liveStop: WidgetLiveStop?): String {
        liveStop ?: return "--"
        val message = liveStop.msg?.trim().orEmpty()
        if (message.isNotEmpty()) {
            return message
        }
        val seconds = liveStop.sec ?: return "--"
        if (seconds <= 0) {
            return "進站中"
        }
        if (seconds < 60) {
            return "即將進站"
        }
        return "${seconds / 60}分"
    }

    private fun routeRequestKey(item: FavoriteWidgetItem): String {
        return "${item.provider}:${item.routeKey}"
    }

    private fun widgetPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(WIDGET_PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    private fun widgetGroupKey(appWidgetId: Int): String {
        return "$WIDGET_GROUP_KEY_PREFIX$appWidgetId"
    }
}

data class FavoriteWidgetItem(
    val provider: String,
    val routeKey: Int,
    val pathId: Int,
    val stopId: Int,
    val routeName: String,
    val stopName: String,
)

data class WidgetLiveStop(
    val sec: Int?,
    val msg: String?,
    val vehicleId: String?,
)
