package com.example.personalsmsgateway

import android.app.*
import android.content.Intent
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.telephony.SmsManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean

class SmsWorkerService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val running = AtomicBoolean(false)
    private val channelId = "sms_gateway_worker"

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.sym_action_email)
            .setContentTitle("Personal SMS Gateway is active")
            .setContentText("Checking your private SMS queue. Tap to open settings.")
            .setContentIntent(open).setOngoing(true).build()
        startForeground(11, notification)
        if (running.compareAndSet(false, true)) {
            scope.launch {
                while (isActive) {
                    try {
                        val url = Prefs.url(this@SmsWorkerService)
                        val key = Prefs.key(this@SmsWorkerService)
                        if (url.startsWith("https://") && key.length >= 40) {
                            val api = ApiClient(url, key)
                            api.heartbeat()
                            val job = api.poll()
                            if (job != null) sendJob(api, job)
                        }
                    } catch (_: Exception) {
                        // Network failures leave jobs to be recovered by the server claim timeout.
                    }
                    delay(30_000)
                }
            }
        }
    }

    private suspend fun sendJob(api: ApiClient, job: SmsJob) {
        try {
            if (checkSelfPermission(android.Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                api.report(job.id, false, "SEND_SMS permission not granted")
                return
            }
            if (!job.recipient.matches(Regex("^\\+[1-9][0-9]{7,14}$"))) {
                api.report(job.id, false, "Invalid international phone number")
                return
            }
            val parts = SmsManager.getDefault().divideMessage(job.message)
            if (parts.size != 1) {
                api.report(job.id, false, "Message is longer than one SMS segment; shorten it and queue again")
                return
            }
            val callback = Intent(this, SmsSentReceiver::class.java).apply {
                action = "com.example.personalsmsgateway.SMS_SENT"
                putExtra("job_id", job.id)
                putExtra("server_url", Prefs.url(this@SmsWorkerService))
                putExtra("device_key", Prefs.key(this@SmsWorkerService))
            }
            val sentIntent = PendingIntent.getBroadcast(
                this, job.id.toInt(), callback,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            SmsManager.getDefault().sendTextMessage(job.recipient, null, job.message, sentIntent, null)
        } catch (e: Exception) {
            try { api.report(job.id, false, (e.message ?: "SMS send failed").take(450)) } catch (_: Exception) {}
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(channelId, "SMS Gateway", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onDestroy() { scope.cancel(); running.set(false); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
