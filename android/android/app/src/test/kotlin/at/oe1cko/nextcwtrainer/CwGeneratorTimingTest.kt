package at.oe1cko.nextcwtrainer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Generator timing against generateCW() (m32_v6.ino, V9.0): after an element
 * inside a character one dit, after a character interCharacterSpace
 * (= Interchar Spc dits), after a word interWordSpace
 * (= max(InterWord Spc, Interchar Spc + 4) dits). 20 WPM = dit 60 ms.
 */
class CwGeneratorTimingTest {

    /** Virtual clock + simulated audio callback that plays the queue in real time. */
    private class Rig(
        val audioRuns: Boolean = true,
        // The stream delivers nothing before this time (then plays normally).
        val deadUntil: Long = 0L,
        // Plays a queued idle gap as silence before the first element.
        val playIdleGaps: Boolean = false,
    ) {
        var t = 0L
        var epoch = 0
        var epochChanges = 0
        var lastEpochChangeAt = 0L
        var startedAt = -1L
        var gapMs = 0L
        val segs = ArrayList<Pair<Boolean, Int>>()
        var total = 0L
        var maxBacklog = 0L
        val idleGaps = ArrayList<Int>()
        val out = object : GenOut {
            override fun setKeyEpoch(epoch: Int) {
                this@Rig.epoch = epoch; startedAt = -1; total = 0; gapMs = 0
                epochChanges++; lastEpochChangeAt = t
            }
            override fun enqueueKey(epoch: Int, on: Boolean, ms: Int): Boolean {
                if (startedAt < 0) startedAt = t
                segs.add(on to ms)
                total += ms
                maxBacklog = maxOf(maxBacklog, total - keyPlayedMs(epoch))
                return true
            }
            override fun enqueueIdleGap(epoch: Int, ms: Int): Boolean {
                idleGaps.add(ms)
                if (playIdleGaps) gapMs = ms.toLong()
                return true
            }
            override fun keyPlayedMs(epoch: Int): Long {
                if (!audioRuns || t < deadUntil || epoch != this@Rig.epoch || startedAt < 0) return -1
                val from = maxOf(startedAt, deadUntil) + gapMs
                return if (t < from) -1 else minOf(total, t - from)
            }
            override fun setRx(on: Boolean) {}
        }
        val gen = CwGenerator(object : GenTone { override val jitter = 0f }, out, { t += it }) { null }
            .also { it.wpm = 20 }

        /** Adjacent segments of the same state, merged: (keyDown, ms). */
        private fun merged(): List<Pair<Boolean, Int>> {
            val m = ArrayList<Pair<Boolean, Int>>()
            for (s in segs) {
                if (m.lastOrNull()?.first == s.first) m[m.size - 1] = s.first to (m.last().second + s.second)
                else m.add(s)
            }
            return m
        }

        /** Lengths in dits of every tone and every gap between tones. */
        fun tones(): List<Int> = merged().filter { it.first }.map { it.second / 60 }
        fun gaps(): List<Int> = merged().filter { !it.first }.map { it.second / 60 }
    }

    @Test fun gapsInsideACharacterAreOneDit() {
        val r = Rig(); r.gen.playWordNow("A", trailingGap = false)   // .-
        assertEquals(listOf(1, 3), r.tones())
        assertEquals(listOf(1), r.gaps())
    }

    @Test fun gapBetweenCharactersIsInterCharSpc() {
        val r = Rig(); r.gen.interCharSpace = 3
        r.gen.playWordNow("EE", trailingGap = false)
        assertEquals(listOf(3), r.gaps())
    }

    @Test fun gapBetweenCharactersFollowsALongerInterCharSpc() {
        val r = Rig(); r.gen.interCharSpace = 9
        r.gen.playWordNow("EE", trailingGap = false)
        assertEquals(listOf(9), r.gaps())
    }

    @Test fun gapBetweenWordsIsInterWordSpcInTotal() {
        val r = Rig(); r.gen.interCharSpace = 3; r.gen.interWordSpace = 7
        r.gen.playWordNow("E E", trailingGap = false)
        assertEquals(listOf(7), r.gaps())
    }

    @Test fun wordGapIsAtLeastInterCharPlusFour() {
        // firmware: interWordSpace = max(InterWord Spc, Interchar Spc + 4)
        val r = Rig(); r.gen.interCharSpace = 9; r.gen.interWordSpace = 7
        r.gen.playWordNow("E E", trailingGap = false)
        assertEquals(listOf(13), r.gaps())
    }

    @Test fun playbackEndsOnlyWhenTheQueueHasBeenPlayed() {
        val r = Rig(); r.gen.playWordNow("A", trailingGap = false)   // 60 + 60 + 180
        assertTrue("ended at ${r.t}", r.t in 300..304)
    }

    @Test fun queueStaysShortlyAheadOfTheAudio() {
        val r = Rig(); r.gen.interCharSpace = 3
        r.gen.playWordNow("HELLO WORLD")
        // the lead plus the longest single segment (rest of the word gap, 4 dits)
        assertTrue("backlog ${r.maxBacklog}", r.maxBacklog <= 100 + 4 * 60 + 2)
    }

    @Test fun callbacksFollowTheAudioNotTheQueue() {
        val r = Rig()
        val at = ArrayList<Long>()
        r.gen.onElement = { _, down -> if (down) at.add(r.t) }
        r.gen.playWordNow("TT", trailingGap = false)                 // dah, 3 dit gap, dah
        assertEquals(2, at.size)
        assertTrue("first ${at[0]}", at[0] <= 2)
        assertTrue("second ${at[1]}", at[1] in 360..364)             // 180 + 180
    }

    @Test fun nextGroupAsksForTheWholeWordGap() {
        val r = Rig(); r.gen.interCharSpace = 3; r.gen.interWordSpace = 7
        r.gen.playWordNow("E", trailingGap = false, afterWordGap = true)
        assertEquals(listOf(420), r.idleGaps)
    }

    @Test fun nextGroupWordGapIsAtLeastInterCharPlusFour() {
        val r = Rig(); r.gen.interCharSpace = 9; r.gen.interWordSpace = 7
        r.gen.playWordNow("E", trailingGap = false, afterWordGap = true)
        assertEquals(listOf(13 * 60), r.idleGaps)
    }

    @Test fun aPlainPlaybackHasNoIdleGap() {
        val r = Rig(); r.gen.playWordNow("E", trailingGap = false)
        assertEquals(emptyList<Int>(), r.idleGaps)
    }

    @Test fun nothingToPlayEndsAtOnce() {
        val r = Rig(); r.gen.playWordNow("", trailingGap = false)
        assertEquals(0L, r.t)
    }

    @Test fun aDeadAudioStreamDoesNotHangPlayback() {
        val r = Rig(audioRuns = false)
        var chars = 0
        r.gen.onChar = { chars++ }
        r.gen.playWordNow("E", trailingGap = false)
        assertEquals(1, chars)
        assertTrue("gave up at ${r.t}", r.t in 1500..1510)
    }

    // #191: an idle gap longer than the stall timeout is waiting, not a dead stream.
    @Test fun aLongIdleGapIsNotAStall() {
        val r = Rig(playIdleGaps = true)
        r.gen.wpm = 5                                   // dit 240 ms, word gap 7 dits = 1680 ms
        r.gen.interCharSpace = 3; r.gen.interWordSpace = 7
        r.gen.playWordNow("E", trailingGap = false, afterWordGap = true)
        assertEquals(listOf(1680), r.idleGaps)
        assertEquals("no new epoch", 1, r.epochChanges)
        assertTrue("ended at ${r.t}", r.t in 1920..1924)   // gap + dit
    }

    // #192: with the stream gone the rest of the playback keeps real time
    // instead of stalling for 1.5 s at every element.
    @Test fun aDeadStreamKeepsRealTime() {
        val r = Rig(audioRuns = false)
        var chars = 0
        r.gen.onChar = { chars++ }
        r.gen.playWordNow("PARIS", trailingGap = false)  // 43 dits = 2580 ms
        assertEquals(5, chars)
        // 120 ms queued when the stream is given up, 1.5 s wait, the rest in real time
        assertTrue("ended at ${r.t}", r.t in 3960..3990)
    }

    // #192: once the stream plays again, the queue takes over again.
    @Test fun theQueueTakesOverWhenTheStreamComesBack() {
        val r = Rig(deadUntil = 2500)
        var chars = 0
        r.gen.onChar = { chars++ }
        r.gen.playWordNow("PARIS PARIS", trailingGap = false)  // 93 dits = 5580 ms
        assertEquals(10, chars)
        assertTrue("last epoch change at ${r.lastEpochChangeAt}", r.lastEpochChangeAt < 2500 + 200)
        assertTrue("ended at ${r.t}", r.t in 6900..7300)
    }
}
