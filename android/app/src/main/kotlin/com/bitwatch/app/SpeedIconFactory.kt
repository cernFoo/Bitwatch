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

    // Rendered at a higher resolution than the status bar actually displays
    // (Android downsamples smoothly), which keeps digits crisp instead of
    // blurry/illegible at real icon size. Note: since Android 5.0, the
    // system renders small icons as a solid alpha mask (ignoring color), so
    // only the shape/coverage of these pixels matters - the paint color
    // itself doesn't need to change.
    private const val SIZE_PX = 144

    // Two-row layout ("84" over "KB/s") instead of one line ("84K"): each
    // row gets the full canvas width to itself, so the number can be drawn
    // noticeably larger than when it had to share a line with a unit
    // suffix. Mirrors the stacked number/unit style some OEM lock screens
    // use for their own built-in network speed indicator.
    private val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    private val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        textAlign = Paint.Align.CENTER
    }

    /**
     * Splits a download speed into a (number, unit) pair for the two-row
     * icon, e.g. (84, "KB/s") or (2.3, "MB/s"). Always KB or MB - sub-KB
     * speeds round to "0"/"KB/s" rather than falling back to a "B/s" unit,
     * since a bytes-per-second reading isn't meaningful at a glance.
     */
    fun formatParts(bytesPerSecond: Long): Pair<String, String> {
        val kb = 1024.0
        val mb = kb * 1024.0
        return if (bytesPerSecond >= mb) {
            "%.1f".format(bytesPerSecond / mb) to "MB/s"
        } else {
            "${(bytesPerSecond / kb).roundToInt()}" to "KB/s"
        }
    }

    fun buildIcon(downloadBytesPerSecond: Long): IconCompat {
        val (number, unit) = formatParts(downloadBytesPerSecond)
        val bitmap = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Scale the number's font size down as it gets longer so 4-char
        // values like "12.3" still fit without clipping.
        numberPaint.textSize = when (number.length) {
            in 0..2 -> 68f
            3 -> 56f
            else -> 46f
        }
        unitPaint.textSize = 26f

        // Top ~60% of the canvas for the number, bottom ~40% for the unit.
        val topRectCenterY = SIZE_PX * 0.32f
        val bottomRectCenterY = SIZE_PX * 0.78f

        val numberY = topRectCenterY - ((numberPaint.descent() + numberPaint.ascent()) / 2f)
        val unitY = bottomRectCenterY - ((unitPaint.descent() + unitPaint.ascent()) / 2f)

        canvas.drawText(number, SIZE_PX / 2f, numberY, numberPaint)
        canvas.drawText(unit, SIZE_PX / 2f, unitY, unitPaint)

        return IconCompat.createWithBitmap(bitmap)
    }
}
