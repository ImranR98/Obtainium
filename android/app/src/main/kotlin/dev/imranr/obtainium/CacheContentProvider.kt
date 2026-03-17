// @author Bikram Agarwal
package dev.imranr.obtainium

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

private const val RELEASE_DIR = "releases"

class CacheContentProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    private fun getFileAndTypeForUri(uri: Uri): Pair<File, String> {
        val firstSegment = uri.pathSegments?.firstOrNull()
        if (firstSegment == RELEASE_DIR) {
            val file = File(context!!.cacheDir, uri.encodedPath!!)
            return Pair(file, "application/vnd.android.package-archive")
        }
        throw SecurityException("Invalid URI: $uri")
    }

    override fun query(
        uri: Uri, projection: Array<out String>?,
        selection: String?, selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val (file, _) = getFileAndTypeForUri(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)
        val row = columns.map { column ->
            when (column) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        cursor.addRow(row.toTypedArray())
        return cursor
    }

    override fun getType(uri: Uri): String = getFileAndTypeForUri(uri).second

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val openMode = when (mode) {
            "r" -> ParcelFileDescriptor.MODE_READ_ONLY
            "w" -> ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
            "rw" -> ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE
            else -> ParcelFileDescriptor.MODE_READ_ONLY
        }
        val file = getFileAndTypeForUri(uri).first
        if (!file.exists()) throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, openMode)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
