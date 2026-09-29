// Device settings the Swift side reads from Java (Android/Platform/Locale+Android.swift): the
// time zone by its IANA identifier, the language list, and a listener for zone changes.
package piru.module

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.LocaleList
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat

class AndroidPlatform {
    companion object {
        private var timeZoneReceiver: BroadcastReceiver? = null

        /// The zone's IANA identifier ("Asia/Shanghai").
        @JvmStatic
        fun timeZoneID(): String = java.util.TimeZone.getDefault().id

        /// The user's languages in order, as BCP 47 tags joined by commas: the per-app
        /// language when one is set, else the device list.
        @JvmStatic
        fun languageTags(): String {
            val app = AppCompatDelegate.getApplicationLocales()
            return if (!app.isEmpty) app.toLanguageTags() else LocaleList.getAdjustedDefault().toLanguageTags()
        }

        /// Tells the app delegate whenever the device's time zone changes.
        @JvmStatic
        fun watchTimeZone(context: Context) {
            if (timeZoneReceiver != null) return
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    PiruAppDelegate.shared.onTimeZoneChanged(timeZoneID())
                }
            }
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(Intent.ACTION_TIMEZONE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            timeZoneReceiver = receiver
        }
    }
}
