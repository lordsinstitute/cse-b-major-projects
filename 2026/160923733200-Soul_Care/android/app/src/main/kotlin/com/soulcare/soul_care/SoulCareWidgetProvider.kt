package com.soulcare.soul_care

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * SoulCare home-screen widget. Reads the last numbers the app saved
 * (score + daily completion) so it works offline and when the app is
 * not running. Taps deep-link into fast logging screens; failures here
 * never affect the main app.
 */
class SoulCareWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val score = widgetData.getInt("soulcare_score", -1)
            val done = widgetData.getInt("soulcare_done", -1)
            val total = widgetData.getInt("soulcare_total", 5)

            val views = RemoteViews(context.packageName, R.layout.soulcare_widget).apply {
                setTextViewText(
                    R.id.widget_score,
                    if (score >= 0) score.toString() else "—",
                )
                setTextViewText(
                    R.id.widget_progress,
                    if (done >= 0) "Today $done / $total complete"
                    else "Today — / — complete",
                )

                // Whole-widget tap: open the app home.
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("soulcare://widget?action=score"),
                    ),
                )
                // Quick actions: fast logging screens.
                setOnClickPendingIntent(
                    R.id.widget_btn_water,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("soulcare://widget?action=water"),
                    ),
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_mood,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("soulcare://widget?action=mood"),
                    ),
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_checkin,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("soulcare://widget?action=checkin"),
                    ),
                )

                // Hide actions until the app has saved at least once.
                val hasData = score >= 0 && done >= 0
                setViewVisibility(
                    R.id.widget_btn_water,
                    if (hasData) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_btn_mood,
                    if (hasData) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_btn_checkin,
                    if (hasData) View.VISIBLE else View.GONE,
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
