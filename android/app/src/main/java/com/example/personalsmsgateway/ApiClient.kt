package com.example.personalsmsgateway

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class SmsJob(val id: Long, val recipient: String, val message: String)

class ApiClient(private val baseUrl: String, private val key: String) {
    private fun post(action: String, body: JSONObject = JSONObject()): JSONObject {
        val clean = baseUrl.trimEnd('/') + "/sms_api.php?action=" + action
        val conn = (URL(clean).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15000
            readTimeout = 15000
            doOutput = true
            setRequestProperty("Authorization", "Bearer $key")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
        }
        return try {
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
            val raw = stream?.bufferedReader()?.use { it.readText() } ?: "{}"
            if (conn.responseCode !in 200..299) throw IllegalStateException("Server HTTP ${conn.responseCode}: $raw")
            JSONObject(raw)
        } finally { conn.disconnect() }
    }

    fun poll(): SmsJob? {
        val response = post("poll")
        if (response.isNull("job")) return null
        val j = response.getJSONObject("job")
        return SmsJob(j.getLong("id"), j.getString("recipient"), j.getString("message"))
    }

    fun heartbeat() { post("heartbeat") }

    fun report(jobId: Long, sent: Boolean, error: String = "") {
        post("result", JSONObject().put("job_id", jobId).put("status", if (sent) "sent" else "failed").put("error", error))
    }
}
