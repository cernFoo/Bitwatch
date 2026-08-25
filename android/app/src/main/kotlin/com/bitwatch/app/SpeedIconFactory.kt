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
        // Bold, not regular: at real status-bar size (the OS downsamples
        // our 144px canvas to roughly 24-33dp), thin regular-weight strokes
        // break apart into illegible fragments once flattened to a 1-bit
        // alpha mask. Bold survives that downsample much better.
        typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }

    /**
     * Splits a download speed into a (number, unit) pair for the two-row
     * icon, e.g. (84, "KB") or (2.3, "MB"). Always KB or MB - sub-KB speeds
     * round to "0"/"KB" rather than falling back to a "B" unit, since a
     * bytes-per-second reading isn't meaningful at a glance. The unit is
     * intentionally just "KB"/"MB" (no "/s" suffix) here - the icon needs to
     * stay as short and bold as possible to survive the downsample to real
     * status-bar size; "per second" is implicit and still spelled out in
     * full in the notification body.
     */
    fun formatParts(bytesPerSecond: Long): Pair<String, String> {
        val kb = 1024.0
        val mb = kb * 1024.0
        return if (bytesPerSecond >= mb) {
            "%.1f".format(bytesPerSecond / mb) to "MB"
        } else {
            "${(bytesPerSecond / kb).roundToInt()}" to "KB"
        }
    }

    fun buildIcon(downloadBytesPerSecond: Long): IconCompat {
        val (number, unit) = formatParts(downloadBytesPerSecond)
        val bitmap = Bitmap.createBitmap(SIZE_PX, SIZE_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Scale the number's font size down as it gets longer so 4-char
        // values like "12.3" still fit without clipping. Pushed larger than
        // before, and the unit dropped to a plain "KB"/"MB" (see
        // formatParts), so both rows read clearly at real icon size.
        numberPaint.textSize = when (number.length) {
            in 0..2 -> 74f
            3 -> 60f
            else -> 50f
        }
        unitPaint.textSize = 32f

        // Top ~58% of the canvas for the number, bottom ~40% for the unit.
        val topRectCenterY = SIZE_PX * 0.34f
        val bottomRectCenterY = SIZE_PX * 0.80f

        val numberY = topRectCenterY - ((numberPaint.descent() + numberPaint.ascent()) / 2f)
        val unitY = bottomRectCenterY - ((unitPaint.descent() + unitPaint.ascent()) / 2f)

        canvas.drawText(number, SIZE_PX / 2f, numberY, numberPaint)
        canvas.drawText(unit, SIZE_PX / 2f, unitY, unitPaint)

        return IconCompat.createWithBitmap(bitmap)
    }
}
