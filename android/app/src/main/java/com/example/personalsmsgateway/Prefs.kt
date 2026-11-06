package com.example.personalsmsgateway

import android.content.Context

object Prefs {
    private const val FILE = "sms_gateway_settings"
    fun save(context: Context, url: String, key: String) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("url", url.trim()).putString("key", key.trim()).apply()
    }
    fun url(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString("url", "https://seojasoos.com/pcmoniter/") ?: ""
    fun key(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString("key", "") ?: ""
}
