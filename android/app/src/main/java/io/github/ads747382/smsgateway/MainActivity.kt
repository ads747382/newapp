package io.github.ads747382.smsgateway

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    private lateinit var url: EditText
    private lateinit var key: EditText
    private lateinit var status: TextView
    private lateinit var enable: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 36, 28, 28)
        }
        layout.addView(TextView(this).apply { text = "SMS Gateway"; textSize = 24f })
        layout.addView(TextView(this).apply { text = "Connect this phone to your own website. A persistent notification appears while sending is enabled." })
        url = EditText(this).apply { hint = "Server URL, e.g. https://your-site.com/sms/"; setText(Prefs.url(this@MainActivity)); isSingleLine = true }
        key = EditText(this).apply { hint = "Device key"; setText(Prefs.key(this@MainActivity)); isSingleLine = true }
        layout.addView(url); layout.addView(key)
        val save = Button(this).apply { text = "Save & connect" }
        enable = Button(this).apply { text = "Enable SMS worker" }
        val stop = Button(this).apply { text = "Pause SMS worker" }
        status = TextView(this).apply { text = "Worker is paused."; textSize = 16f }
        layout.addView(save); layout.addView(enable); layout.addView(stop); layout.addView(status)
        layout.addView(TextView(this).apply {
            text = "Only use for people who agreed to receive your messages. Keep the phone online with an active SIM and SMS balance. The app sends one SMS segment per job."
            textSize = 13f
        })
        setContentView(ScrollView(this).apply { addView(layout) })

        save.setOnClickListener {
            if (!url.text.toString().startsWith("https://")) {
                status.text = "Use an HTTPS server URL."
            } else if (key.text.toString().length < 40) {
                status.text = "Enter the device key created on your website."
            } else {
                Prefs.save(this, url.text.toString(), key.text.toString())
                status.text = "Settings saved."
            }
        }
        enable.setOnClickListener {
            Prefs.save(this, url.text.toString(), key.text.toString())
            if (Prefs.key(this).length < 40 || !Prefs.url(this).startsWith("https://")) {
                status.text = "Save a valid HTTPS URL and device key first."
                return@setOnClickListener
            }
            requestPermissionsAndStart()
        }
        stop.setOnClickListener {
            stopService(Intent(this, SmsWorkerService::class.java))
            status.text = "Worker paused."
        }
    }

    private fun requestPermissionsAndStart() {
        val needed = mutableListOf(Manifest.permission.SEND_SMS)
        if (Build.VERSION.SDK_INT >= 33) needed.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = needed.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 10)
        } else startWorker()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 10 && ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) startWorker()
        else status.text = "SMS permission is required to send queued messages."
    }

    private fun startWorker() {
        ContextCompat.startForegroundService(this, Intent(this, SmsWorkerService::class.java))
        status.text = "SMS worker enabled. Check the persistent notification."
    }
}
