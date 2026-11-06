package com.example.personalsmsgateway

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SmsSentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Read the result code BEFORE goAsync(): afterwards getResultCode() always returns 0.
        val code = resultCode
        val pending = goAsync()
        Thread {
            try {
                val id = intent.getLongExtra("job_id", -1L)
                val url = intent.getStringExtra("server_url") ?: ""
                val key = intent.getStringExtra("device_key") ?: ""
                if (id > 0 && url.startsWith("https://") && key.length >= 40) {
                    val api = ApiClient(url, key)
                    if (code == Activity.RESULT_OK) api.report(id, true)
                    else api.report(id, false, "Android telephony send result code: $code")
                }
            } catch (_: Exception) {
                // Server claim timeout will recover the job if callback cannot reach server.
            } finally { pending.finish() }
        }.start()
    }
}
