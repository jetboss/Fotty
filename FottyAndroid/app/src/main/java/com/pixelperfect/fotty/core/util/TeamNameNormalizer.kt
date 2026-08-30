package com.pixelperfect.fotty.core.util

object TeamNameNormalizer {
    /**
     * Normalizes team names for robust cross-provider matching.
     * Strips suffixes like "FC", "AF", "CP", "Lisbon", etc.
     */
    fun normalize(name: String): String {
        return name.lowercase()
            .replace("football club", "")
            .replace("club de fútbol", "")
            .replace("fc", "")
            .replace("afc", "")
            .replace("sc", "")
            .replace("cp", "")
            .replace("lisbon", "")
            .replace("madrid", "") // Madrid is often ambiguous between Real/Atletico but helps in specific tokens
            .replace("-", " ")
            .trim()
            .split(" ")
            .filter { it.length > 2 }
            .joinToString(" ")
    }

    /**
     * Performs a fuzzy match between two team names.
     */
    fun fuzzyMatch(name1: String, name2: String): Boolean {
        val n1 = normalize(name1)
        val n2 = normalize(name2)
        
        if (n1.isEmpty() || n2.isEmpty()) return false
        
        return n1.contains(n2) || n2.contains(n1)
    }
}
