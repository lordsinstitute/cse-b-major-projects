package com.soulcare.soul_care

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        applyScreenshotFlag()
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        applyScreenshotFlag()
    }

    private fun applyScreenshotFlag() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val allowScreenshots = prefs.getBoolean("flutter.allow_screenshots", false)
        if (allowScreenshots) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
