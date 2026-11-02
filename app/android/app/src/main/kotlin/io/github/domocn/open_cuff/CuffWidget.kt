package io.github.domocn.open_cuff

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// Home screen widget: latest reading and when. The app writes the text through home_widget after each sync.
class CuffWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.cuff_widget).apply {
                setTextViewText(R.id.widget_bp, widgetData.getString("bp", "No reading yet"))
                setTextViewText(R.id.widget_detail, widgetData.getString("detail", "Open Cuff"))
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
