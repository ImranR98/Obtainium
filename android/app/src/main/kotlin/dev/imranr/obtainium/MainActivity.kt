package dev.imranr.obtainium

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        intent?.let {
            setIntent(transformShareIntent(it))
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val newIntent = transformShareIntent(intent)
        setIntent(newIntent)
        super.onNewIntent(newIntent)
    }

    private fun transformShareIntent(intent: Intent): Intent {
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            val match = sharedText?.let { """https?://[^\s]+""".toRegex().find(it) } // Extract URL from shared text
            if (match != null) {
                val url = match.value.trimEnd('.', ',', ';', '!', '?', ')') // Trim potential trailing punctuation
                intent.apply { // "Redirect" the intent
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("obtainium://add/$url")
                }
            } else {
                Toast.makeText(this, "No URL found in shared text", Toast.LENGTH_SHORT).show()
            }
        }
        return intent
    }
}
