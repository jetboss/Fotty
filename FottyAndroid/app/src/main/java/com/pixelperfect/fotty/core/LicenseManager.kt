package com.pixelperfect.fotty.core

import android.content.Context
import android.content.SharedPreferences
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LicenseManager @Inject constructor(
    private val context: Context
) {
    private val prefs: SharedPreferences = context.getSharedPreferences("fotty_license_prefs", Context.MODE_PRIVATE)
    
    // The "Magic Key" - You can change this to anything you want
    private val MAGIC_PRO_KEY = "FOTTY-PRO-2026-X99"

    var isProUser: Boolean
        get() = prefs.getBoolean("is_pro_user", false)
        set(value) = prefs.edit().putBoolean("is_pro_user", value).apply()

    fun verifyKey(input: String): Boolean {
        if (input.trim().uppercase() == MAGIC_PRO_KEY) {
            isProUser = true
            return true
        }
        return false
    }
}
