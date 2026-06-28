package dev.imranr.obtainium

import android.content.IIntentReceiver
import android.content.IIntentSender
import android.content.Intent
import android.content.IntentSender
import android.os.Bundle
import android.os.IBinder

object ShizukuIntentSenderHelper {
    fun newIntentSender(binder: IIntentSender): IntentSender {
        return IntentSender::class.java.getConstructor(IIntentSender::class.java)
            .newInstance(binder)
    }

    class IIntentSenderAdaptor(private val listener: (Intent) -> Unit) : IIntentSender.Stub() {
        override fun send(
            code: Int,
            intent: Intent,
            resolvedType: String?,
            finishedReceiver: IIntentReceiver?,
            requiredPermission: String?,
            options: Bundle?,
        ): Int {
            listener(intent)
            return 0
        }

        override fun send(
            code: Int,
            intent: Intent,
            resolvedType: String?,
            whitelistToken: IBinder?,
            finishedReceiver: IIntentReceiver?,
            requiredPermission: String?,
            options: Bundle?,
        ) {
            listener(intent)
        }
    }
}
