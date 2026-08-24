package com.bitwatch.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.core.graphics.drawable.IconCompat
import kotlin.math.roundToInt

/**
 * Renders the current download speed as a small flat-white bitmap so it can
 * be used as the notification's status bar icon text (per spec: "Display
 * Download Speed ONLY in the status bar icon/text"). Android's status bar
 * only accepts an Icon/IconCompat for setSmallIcon, not arbitrary text, so we
 * draw the number onto a transparent bitmap each tick and wrap it as an
 * IconCompat - the same trick used by many battery/network-monitor apps.
 */
object SpeedIconFactory {

    // Status bar icons are small; keep this compact and legible at ~48-64px.
    private const val SIZE_PX = 96

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    /**
     * Builds a compact label like "512K" or "2.3M" (kept short so it stays
     * legible at status-bar icon size) for the given download bytes/sec.
     */
    fun formatCompact(bytesPerSecond: Long): String {
        val kb = 1024.0
        val mb = kb * 1024.0
        return when {
            bytesPerSecond >= mb -> "${"%.1f".format(bytesPerSecond / mb)}M"
            bytesPerSecond >= kb -> "${(bytesPerSecond / kb).roundToInt()}K"
            else -> "${bytesPerSecond}B"
        }
    }

    fun buildIcon(downloadBytesPerSecond: Long): IconCompat {
        val label = formatCompact(downloadBytesPerSecond)
        val bitmap = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Scale font size down as the label gets longer so 4-char labels
        // like "12.3M" still fit without clipping.
        val fontSize = when (label.length) {
            in 0..2 -> 52f
            3 -> 42f
            4 -> 34f
            else -> 28f
        }
        paint.textSize = fontSize

        val yPos = (SIZE_PX / 2f) - ((paint.descent() + paint.ascent()) / 2f)
        canvas.drawText(label, SIZE_PX / 2f, yPos, paint)

        return IconCompat.createWithBitmap(bitmap)
    }
}
