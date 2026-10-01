package at.oe1cko.nextcwtrainer

import kotlin.math.sqrt

/**
 * Adaptive straight-key decoder, a port of the firmware's Decoder
 * (MorseDecoder.cpp, "Version 6 and newer": decode(), ON_(), OFF_(),
 * recalculateDit/Dah). It measures the operator's own dit and dah lengths
 * (running averages) and derives the dit/dah threshold and the character and
 * word gaps from them, instead of from the configured WPM.
 *
 * Pure logic, no Android or threading: the caller passes the time in ms. Only
 * the straight-key branch of CwKeyer uses it; the paddle code never does.
 *
 * Differences from the firmware: no noise blanker (touch and phone inputs do
 * not bounce) and the start speed is a parameter (the firmware starts at fixed
 * values and never reads its configured WPM).
 */
class StraightKeyDecoder {

    private enum class State { LOW, HIGH, INTER_ELEMENT, INTER_CHAR }

    /** Measured speed in WPM (firmware d_wpm), updated at every character end. */
    var wpm: Int = 20
        private set

    /**
     * Echo Trainer: word gap = this many dits (InterWord Spc + 1). 0 = the
     * normal 5 dits. Like the firmware it only applies up to 30 WPM; above that
     * the speed-dependent 5.5 / 6 dits win.
     */
    @Volatile var echoWordGapDits: Int = 0

    private var ditAvg = 60L
    private var dahAvg = 180L
    private var state = State.LOW
    private var startLow = 0L
    private var startHigh = 0L
    private var lowDuration = Long.MAX_VALUE
    private var pendingSymbol = false
    private var wordOpen = false      // a character was emitted since the last word end

    init { reset(20) }

    /** Restart the measurement from a start speed (also on screen entry). */
    @Synchronized
    fun reset(startWpm: Int) {
        val w = startWpm.coerceIn(5, 60)
        ditAvg = 1200L / w
        dahAvg = ditAvg * 3
        wpm = w
        state = State.LOW
        startLow = 0L
        startHigh = 0L
        lowDuration = Long.MAX_VALUE
        pendingSymbol = false
        wordOpen = false
    }

    /** Forget a half-finished character/word but keep the measured speed. */
    @Synchronized
    fun softReset() {
        state = State.LOW
        startLow = 0L
        startHigh = 0L
        lowDuration = Long.MAX_VALUE
        pendingSymbol = false
        wordOpen = false
    }

    /** Key went down at [now]. */
    @Synchronized
    fun keyDown(now: Long) {
        if (state == State.HIGH) return
        // ON_(): a pause shorter than 2.4 dits is an inter-element pause and
        // adjusts the dit length. After a character or word gap it is longer.
        lowDuration = if (state == State.LOW && startLow == 0L) Long.MAX_VALUE else now - startLow
        startHigh = now
        if (lowDuration < ditAvg * 2.4) recalculateDit(lowDuration)
        state = State.HIGH
    }

    /** Key went up at [now]. Returns "·" or "—", or null for a filtered glitch. */
    @Synchronized
    fun keyUp(now: Long): String? {
        if (state != State.HIGH) return null
        // OFF_()
        val threshold = (ditAvg * sqrt(dahAvg.toDouble() / ditAvg)).toLong()
        val high = now - startHigh
        startLow = now
        state = State.INTER_ELEMENT
        if (high > ditAvg * 0.5 && high < dahAvg * 2.5) {
            return if (high < threshold) {
                recalculateDit(high); pendingSymbol = true; "·"
            } else {
                recalculateDah(high); pendingSymbol = true; "—"
            }
        }
        return null
    }

    /**
     * Call regularly while the key is up. Returns " " at the end of a
     * character, "  " at the end of a word (after the " "), otherwise null.
     */
    @Synchronized
    fun tick(now: Long): String? {
        when (state) {
            State.INTER_ELEMENT -> {
                lowDuration = now - startLow
                val lack = when { wpm > 35 -> 2.4; wpm > 30 -> 2.3; else -> 2.2 }
                if (lowDuration > lack * ditAvg) {
                    val m = (7200L / (dahAvg + 3 * ditAvg)).toInt()
                    wpm = (wpm + m) / 2
                    state = State.INTER_CHAR
                    return if (pendingSymbol) { pendingSymbol = false; wordOpen = true; " " } else null
                }
            }
            State.INTER_CHAR -> {
                lowDuration = now - startLow
                val lack = when {
                    wpm > 35 -> 6.0
                    wpm > 30 -> 5.5
                    echoWordGapDits > 0 -> echoWordGapDits.toDouble()
                    else -> 5.0
                }
                if (lowDuration > lack * ditAvg) {
                    state = State.LOW
                    if (!wordOpen) return null    // only a filtered glitch, no word
                    wordOpen = false
                    return "  "
                }
            }
            else -> {}
        }
        return null
    }

    private fun recalculateDit(duration: Long) {
        ditAvg = (4 * ditAvg + duration) / 5
    }

    private fun recalculateDah(duration: Long) {
        if (duration > 2 * dahAvg) {          // very rapid slow-down: adjust faster
            dahAvg = (dahAvg + 2 * duration) / 3
            ditAvg = ditAvg / 2 + dahAvg / 6
        } else {
            dahAvg = (3 * ditAvg + dahAvg + duration) / 3
        }
    }
}
