package dev.imranr.obtainium.revanced

import android.content.Context
import app.revanced.library.ApkSigner
import app.revanced.library.ApkUtils
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.security.UnrecoverableKeyException
import java.util.Date
import kotlin.time.Duration.Companion.days

/**
 * Owns Obtainium's signing keystore, used to re-sign patched APKs. Ported from
 * ReVanced Manager's KeystoreManager, with the Koin/PreferencesManager DI stripped
 * out since Obtainium has no DI container - alias/password are passed in by the
 * Dart side (which persists them via SharedPreferences) on every call instead.
 */
class KeystoreManager(context: Context) {
    companion object {
        const val DEFAULT_ALIAS = "Obtainium"
        const val DEFAULT_PASSWORD = "Obtainium"
        private val eightYearsFromNow: Date
            get() = Date(System.currentTimeMillis() + (8 * 365).days.inWholeMilliseconds)
    }

    private val keystorePath: File = context.applicationContext
        .getDir("signing", Context.MODE_PRIVATE)
        .resolve("obtainium.keystore")

    fun hasKeystore(): Boolean = keystorePath.exists()

    /** Generates a new self-signed keystore, overwriting any existing one. */
    fun regenerate(alias: String = DEFAULT_ALIAS, password: String = DEFAULT_PASSWORD) {
        val keyCertPair = ApkSigner.newPrivateKeyCertificatePair(alias, eightYearsFromNow)
        val ks = ApkSigner.newKeyStore(
            setOf(ApkSigner.KeyStoreEntry(alias, password, keyCertPair))
        )
        keystorePath.parentFile?.mkdirs()
        keystorePath.outputStream().use { ks.store(it, null) }
    }

    /**
     * Validates and imports a user-supplied keystore. Returns false (without
     * modifying the stored keystore) if the alias/password don't resolve to a
     * usable private key entry.
     */
    fun import(alias: String, password: String, keystoreBytes: ByteArray): Boolean {
        try {
            val ks = ApkSigner.readKeyStore(ByteArrayInputStream(keystoreBytes), null)
            ApkSigner.readPrivateKeyCertificatePair(ks, alias, password)
        } catch (_: UnrecoverableKeyException) {
            return false
        } catch (_: IllegalArgumentException) {
            return false
        }
        keystorePath.parentFile?.mkdirs()
        Files.write(keystorePath.toPath(), keystoreBytes)
        return true
    }

    /** Returns the raw keystore bytes, or null if no keystore exists yet. */
    fun export(): ByteArray? {
        if (!hasKeystore()) return null
        return keystorePath.readBytes()
    }

    /** Signs [input] with the stored keystore, writing the result to [output]. */
    fun sign(input: File, output: File, alias: String, password: String) {
        val details = ApkUtils.KeyStoreDetails(
            keyStore = keystorePath,
            keyStorePassword = null,
            alias = alias,
            password = password,
        )
        ApkUtils.signApk(input, output, alias, details)
    }
}
