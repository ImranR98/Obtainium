package dev.imranr.obtainium

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileInputStream

class DefaultSystemFont {
    fun get(): String? {
        return try {
            val file = File("/system/etc/fonts.xml")
            val fileStream = FileInputStream(file)
            parseFontsFileStream(fileStream)
        } catch (_: Exception) {
            null
        }
    }

    private fun parseFontsFileStream(fileStream: FileInputStream): String {
        fileStream.use { stream ->
            val parser = Xml.newPullParser()
            parser.setInput(stream, null)
            parser.nextTag()
            return parseFonts(parser)
        }
    }

    private fun parseFonts(parser: XmlPullParser): String {
        while (parser.name != "font") { parser.next() }
        parser.next()
        return "/system/fonts/" + parser.text.trim()
    }
}