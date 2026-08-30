package com.pixelperfect.fotty.core.utils

import android.util.Base64
import java.nio.charset.StandardCharsets

object SecurityUtils {
    /**
     * Decodes a Base64 string at runtime to hide sensitive URLs from static analysis.
     */
    fun decode(encoded: String): String {
        return try {
            val data = Base64.decode(encoded, Base64.DEFAULT)
            String(data, StandardCharsets.UTF_8)
        } catch (e: Exception) {
            ""
        }
    }
}
