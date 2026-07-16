package dev.imranr.obtainium.revanced

import app.revanced.library.setOptions
import app.revanced.patcher.patch.Patch
import app.revanced.patcher.patch.loadPatches
import java.io.File
import kotlin.reflect.KType
import kotlin.reflect.full.withNullability
import kotlin.reflect.typeOf

/**
 * Loads a compiled ReVanced patch bundle (a jar of patch classes) and exposes only
 * the universal patches (those with no compatiblePackages restriction) along with
 * their configurable options, for display in Obtainium's per-app patch-config UI.
 *
 * Obtainium intentionally only supports universal patches (see plan) - patches
 * that require a specific target package are filtered out entirely.
 */
object PatchBundleLoader {
    fun listUniversalPatches(bundlePath: String): List<Map<String, Any?>> {
        val patches = loadPatches(File(bundlePath))
        return patches
            .filter { it.compatiblePackages == null }
            .map { patch ->
                mapOf(
                    "name" to (patch.name ?: ""),
                    "description" to (patch.description ?: ""),
                    "options" to patch.options.values.map { option ->
                        mapOf(
                            "key" to option.name,
                            "description" to (option.description ?: ""),
                            "required" to option.required,
                            "type" to simpleTypeName(option.type),
                            "default" to option.default,
                        )
                    },
                )
            }
    }

    /** Collapses KType down to the handful of primitive shapes the Dart-side form understands. */
    private fun simpleTypeName(type: KType): String {
        val nonNull = type.withNullability(false)
        return when (nonNull) {
            typeOf<String>() -> "string"
            typeOf<Boolean>() -> "boolean"
            typeOf<Int>(), typeOf<Long>() -> "integer"
            typeOf<List<String>>() -> "stringList"
            else -> "string"
        }
    }

    /**
     * Resolves the caller-selected universal patches by name and applies the
     * caller-supplied option values (Dart's PatchConfig) via revanced-library's
     * setOptions. Throws if an option key/value doesn't match what the patch
     * declares - the caller (PatchEngine) treats that as a patch failure.
     */
    fun resolveSelectedPatches(
        bundlePath: String,
        selectedPatchNames: List<String>,
        options: Map<String, Map<String, Any?>>,
    ): Set<Patch<*>> {
        val allPatches = loadPatches(File(bundlePath))
        val selected = allPatches
            .filter { it.compatiblePackages == null && it.name in selectedPatchNames }
            .toSet()
        selected.setOptions(options)
        return selected
    }
}
