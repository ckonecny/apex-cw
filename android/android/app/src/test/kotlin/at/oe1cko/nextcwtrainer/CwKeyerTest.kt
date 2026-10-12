package at.oe1cko.nextcwtrainer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keyer behaviour against the firmware's doPaddleIambic() (m32_v6.ino, V9.0).
 * Fake clock, 1 ms steps; 20 WPM = dit 60 ms, dah 180 ms, gap 60 ms.
 * Expected sequences are derived by hand from the firmware source.
 */
class CwKeyerTest {

    private class Sink : KeySink {
        var on = false
        override fun setPlaying(on: Boolean) { this.on = on }
    }

    private class Rig(mode: CwKeyer.Mode = CwKeyer.Mode.IAMBIC_A) {
        var t = 1_000L
        val sink = Sink()
        val keyer = CwKeyer(sink) { t }.also { it.wpm = 20; it.mode = mode }
        val out = StringBuilder()
        init { keyer.onSymbol = { out.append(it) } }

        /** Paddle levels at the given times (ms from now), run to [end]. */
        fun run(end: Int, vararg ev: Triple<Int, Boolean, Boolean>) {
            val base = t
            val events = ev.sortedBy { it.first }.toMutableList()
            while (t - base < end) {
                while (events.isNotEmpty() && events[0].first <= t - base) {
                    val e = events.removeAt(0)
                    keyer.setInputs(e.second, e.third)
                }
                keyer.tick()
                t += 1
            }
        }
        fun symbols() = out.toString().replace(" ", "").replace("  ", "")
    }

    private fun at(ms: Int, dit: Boolean, dah: Boolean) = Triple(ms, dit, dah)

    @Test fun singleDitTap() {
        val r = Rig()
        r.run(400, at(0, true, false), at(30, false, false))
        assertEquals("·", r.symbols())
    }

    @Test fun squeezeAlternatesAndStartsWithDit() {
        val r = Rig()
        // both down together, released at 500 ms
        r.run(1000, at(0, true, true), at(500, false, false))
        assertTrue(r.symbols(), r.symbols().startsWith("·—·—"))
    }

    @Test fun squeezeStartsWithDitEvenAfterACharacterEndedInDit() {
        val r = Rig()
        r.run(800, at(0, true, false), at(30, false, false),
              at(600, true, true), at(1300, false, false))
        // the second character must again start with a dit
        assertTrue(r.out.toString(), r.symbols().startsWith("··—"))
    }

    @Test fun iambicAForgetsAnOppositeTapDuringTheElement() {
        val r = Rig()
        // dit held 0..40, dah tapped 10..30 while the dit sounds
        r.run(600, at(0, true, false), at(10, true, true), at(30, true, false), at(40, false, false))
        assertEquals("·", r.symbols())
    }

    @Test fun iambicBForgetsATapBeforeItsWindow() {
        val r = Rig(CwKeyer.Mode.IAMBIC_B)
        // window opens at 2 + 75 % of 60 ms = 47 ms; tap 10..30 is before it
        r.run(600, at(0, true, false), at(10, true, true), at(30, true, false), at(40, false, false))
        assertEquals("·", r.symbols())
    }

    @Test fun iambicBStoresATapInsideItsWindow() {
        val r = Rig(CwKeyer.Mode.IAMBIC_B)
        // dah tapped 50..55, inside the window (47..60 ms)
        r.run(600, at(0, true, false), at(50, true, true), at(55, true, false), at(58, false, false))
        assertEquals("·—", r.symbols())
    }

    @Test fun oppositeTapInTheGapAfterTheLatencyWindowCounts() {
        val r = Rig()
        // dit 0..60, gap 60..120, latency window 60..90; dah tap at 95..100
        r.run(600, at(0, true, false), at(20, false, false), at(95, false, true), at(100, false, false))
        assertEquals("·—", r.symbols())
    }

    @Test fun ultimaticLastClosedPaddleRepeats() {
        val r = Rig(CwKeyer.Mode.ULTIMATIC)
        // dit down, dah joins at 20 ms, both held until 700 ms
        r.run(1200, at(0, true, false), at(20, true, true), at(700, false, false))
        val s = r.symbols()
        assertTrue(s, s.startsWith("·——"))
        assertFalse(s, s.contains("·—·"))      // never alternates
        assertTrue(s, s.drop(1).all { it == '—' })
    }

    @Test fun ultimaticDitJoiningADahTakesOver() {
        val r = Rig(CwKeyer.Mode.ULTIMATIC)
        r.run(1200, at(0, false, true), at(20, true, true), at(700, false, false))
        val s = r.symbols()
        assertTrue(s, s.startsWith("—··"))
        assertTrue(s, s.drop(1).all { it == '·' })
    }

    @Test fun nonSqueezeRepeatsTheFirstElementWhenSqueezed() {
        val r = Rig(CwKeyer.Mode.NON_SQUEEZE)
        r.run(1000, at(0, true, true), at(400, false, false))
        val s = r.symbols()
        assertTrue(s, s.length >= 3)
        // The opposite paddle is latched 3 ms into every element (firmware
        // curtistimer = 3) and stays latched, so letting go mid-element
        // leaves one trailing dah. Until then the dit repeats: no alternation.
        assertTrue(s, s.removeSuffix("—").all { it == '·' })
        val r2 = Rig(CwKeyer.Mode.NON_SQUEEZE)
        r2.run(1500, at(0, false, true), at(10, true, true), at(700, false, false))
        assertTrue(r2.symbols(), r2.symbols().removeSuffix("·").all { it == '—' })
    }

    @Test fun wordGapIsReportedOnceAfterTheConfiguredDits() {
        val r = Rig()
        r.keyer.wordGapDits = 6
        r.run(1500, at(0, true, false), at(30, false, false))
        assertEquals(1, Regex("  ").findAll(r.out.toString()).count())
    }

    @Test fun autoCharSpacingHoldsBackTheNextCharacter() {
        val r = Rig()
        r.keyer.acsValue = 1   // gate = 2 dits = 120 ms after the character
        // char ends ~120 ms after the first press; press again right after
        r.run(1000, at(0, true, false), at(20, false, false), at(130, true, false), at(140, false, false))
        // the second dit is only keyed once the gate is open, but not lost
        assertEquals("··", r.symbols())
    }

    @Test fun stopThenStartRightAwayLeavesAWorkingKeyerThread() {
        val sink = Sink()
        val k = CwKeyer(sink)
        k.start(); k.stop(); k.start()
        val got = StringBuilder()
        k.onSymbol = { got.append(it) }
        k.setInputs(true, false)
        Thread.sleep(150)
        k.setInputs(false, false)
        Thread.sleep(100)
        k.stop()
        assertTrue(got.toString(), got.contains("·"))
    }
}
