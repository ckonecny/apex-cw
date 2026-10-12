package at.oe1cko.nextcwtrainer

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Generator timing against generateCW() (m32_v6.ino, V9.0): after an element
 * inside a character one dit, after a character interCharacterSpace
 * (= Interchar Spc dits), after a word interWordSpace
 * (= max(InterWord Spc, Interchar Spc + 4) dits). 20 WPM = dit 60 ms.
 */
class CwGeneratorTimingTest {

    /** Virtual clock + recorder: (time, keyDown) transitions. */
    private class Rig {
        var t = 0L
        val ev = ArrayList<Pair<Long, Boolean>>()
        val out = object : GenOut {
            override fun setPlaying(on: Boolean) { if (ev.lastOrNull()?.second != on) ev.add(t to on) }
            override fun setRx(on: Boolean) {}
        }
        val gen = CwGenerator(object : GenTone { override val jitter = 0f }, out, { t += it }) { null }
            .also { it.wpm = 20 }

        /** Lengths in dits of every tone and every gap between tones. */
        fun tones(): List<Long> = ev.chunked(2).filter { it.size == 2 }.map { (it[1].first - it[0].first) / 60 }
        fun gaps(): List<Long> = ev.windowed(3, 2).filter { it.size == 3 }.map { (it[2].first - it[1].first) / 60 }
    }

    @Test fun gapsInsideACharacterAreOneDit() {
        val r = Rig(); r.gen.playWordNow("A", trailingGap = false)   // .-
        assertEquals(listOf(1L, 3L), r.tones())
        assertEquals(listOf(1L), r.gaps())
    }

    @Test fun gapBetweenCharactersIsInterCharSpc() {
        val r = Rig(); r.gen.interCharSpace = 3
        r.gen.playWordNow("EE", trailingGap = false)
        assertEquals(listOf(3L), r.gaps())
    }

    @Test fun gapBetweenCharactersFollowsALongerInterCharSpc() {
        val r = Rig(); r.gen.interCharSpace = 9
        r.gen.playWordNow("EE", trailingGap = false)
        assertEquals(listOf(9L), r.gaps())
    }

    @Test fun gapBetweenWordsIsInterWordSpcInTotal() {
        val r = Rig(); r.gen.interCharSpace = 3; r.gen.interWordSpace = 7
        r.gen.playWordNow("E E", trailingGap = false)
        assertEquals(listOf(7L), r.gaps())
    }

    @Test fun wordGapIsAtLeastInterCharPlusFour() {
        // firmware: interWordSpace = max(InterWord Spc, Interchar Spc + 4)
        val r = Rig(); r.gen.interCharSpace = 9; r.gen.interWordSpace = 7
        r.gen.playWordNow("E E", trailingGap = false)
        assertEquals(listOf(13L), r.gaps())
    }
}
