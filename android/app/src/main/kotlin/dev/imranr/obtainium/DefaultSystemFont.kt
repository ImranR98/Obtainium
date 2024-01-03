package dev.imranr.obtainium

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileInputStream

class DefaultSystemFont {
    fun get(): String {
        return try {
            val file = File("/system/etc/fonts.xml")
            val fileStream = FileInputStream(file)
            parseFontsFileStream(fileStream)
        } catch (e: Exception) {
            e.message ?: "Unknown fonts.xml parsing exception"
        }
    }

    private fun parseFontsFileStream(fileStream: FileInputStream): String {
        fileStream.use { stream ->
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(stream, null)
            parser.nextTag()
            return parseFonts(parser)
        }
    }

    private fun parseFonts(parser: XmlPullParser): String {
        while (!((parser.next() == XmlPullParser.END_TAG) && (parser.name == "family"))) {
            if ((parser.eventType == XmlPullParser.START_TAG) && (parser.name == "font")
                && (parser.getAttributeValue(null, "style") == "normal")
                && (parser.getAttributeValue(null, "weight") == "400")) {
                break
            }
        }
        parser.next()
        val fontFile = parser.text.trim()
        if (fontFile == "") {
            throw NoSuchFieldException("The font filename couldn't be found in fonts.xml")
        }
        return "/system/fonts/$fontFile"
    }
}