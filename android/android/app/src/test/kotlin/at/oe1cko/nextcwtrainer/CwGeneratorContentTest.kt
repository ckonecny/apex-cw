package at.oe1cko.nextcwtrainer

import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Content generation against fetchNewWord()/getRandomChars()/Koch (V9.0). Seeded, so reproducible. */
class CwGeneratorContentTest {

    private fun gen(seed: Int = 1) = CwGenerator(
        object : GenTone { override val jitter = 0f },
        rng = Random(seed),
    ) { path -> if (path.endsWith("en.txt")) "hello 10\nworld 10\nmorse 10\n" else null }

    @Test fun abbreviationListIsTheFirmwareOne() {
        val a = gen().wordLists()["abbrevs"]!!
        assertEquals(245, a.size)                       // ABBREV_NUMBER_OF_ELEMENTS
        assertEquals("Z", a.last())
        assertEquals(9, a.count { it.length == 1 })     // ABBREV_POINTER[1] = 236 -> 9 one-letter entries
    }

    @Test fun plainMixedIsWordAbbrevCallOrSinglePunctPro() {
        val g = gen(); g.mode = CwGenerator.Mode.MIXED
        val words = setOf("HELLO", "WORLD", "MORSE")
        val abbrevs = g.wordLists()["abbrevs"]!!.toSet()
        val n = 8000
        val kinds = HashMap<String, Int>()
        repeat(n) {
            val c = g.nextContent()
            val k = when {
                c in words -> "word"
                c in abbrevs -> "abbrev"
                c.startsWith("<") || (c.length == 1 && !c[0].isLetterOrDigit()) -> "single"
                else -> "call"
            }
            kinds.merge(k, 1, Int::plus)
        }
        // random(4): each about a quarter
        for (k in listOf("word", "abbrev", "call", "single"))
            assertTrue("$k ${kinds[k]} of $n", (kinds[k] ?: 0) in (n * 0.22).toInt()..(n * 0.28).toInt())
    }

    @Test fun nonKochBoostIsAWeightedDrawNotARedraw() {
        // practice set = a..y (25 of the 51 characters of "All"), Strong = weight 8
        // member share = 25*8 / (25*8 + 26) = 0.885; the Koch-style 8 redraws would give 0.995
        val g = gen(); g.mode = CwGenerator.Mode.RANDOM_CHARS
        g.kochActive = false; g.randomOption = 0; g.groupLength = 5
        g.practiceChars = ('a'..'y').map { it.toString() }
        g.boostLevel = 2
        var member = 0; var total = 0
        repeat(6000) {
            val s = g.nextContent()
            // count single-letter draws only; prosign mnemonics like <AS> are upper case
            s.forEach { ch -> if (ch.isLowerCase() || ch.isDigit() || ch in ".,:-/=?@+") { total++; if (ch in 'a'..'y') member++ } }
        }
        val share = member.toDouble() / total
        assertTrue("share $share", share in 0.86..0.91)
    }

    @Test fun kochDrawsTheLastThirdMoreOften() {
        // firmware: 2 of 3 draws from the whole set, 1 of 3 from its last third
        val g = gen(); g.mode = CwGenerator.Mode.RANDOM_CHARS
        g.kochActive = true; g.kochLevel = 12; g.groupLength = 5
        val last = g.kochChars.take(12).drop(8).toSet()      // 2*12/3 = 8
        var inLast = 0; var total = 0
        repeat(4000) { g.nextContent().forEach { c -> total++; if (c.toString() in last) inLast++ } }
        val share = inLast.toDouble() / total               // 1/3 + 2/3 * 4/12 = 0.556
        assertTrue("share $share", share in 0.52..0.59)
    }

    @Test fun kochBoostRedrawsUpToThreeTimesForModerate() {
        // active set of 2 (M, K), practice = K. Base P(K) with the last-third rule over
        // 2 chars: 1/3 from [1,2) = K only, 2/3 uniform: 1/3 + 2/3 * 1/2 = 2/3.
        // Three tries: 1 - (1/3)^3 = 0.963
        val g = gen(); g.mode = CwGenerator.Mode.RANDOM_CHARS
        g.kochActive = true; g.kochLevel = 2; g.groupLength = 5
        g.practiceChars = listOf("K"); g.boostLevel = 1
        var k = 0; var total = 0
        repeat(4000) { g.nextContent().forEach { c -> total++; if (c == 'K') k++ } }
        val share = k.toDouble() / total
        assertTrue("share $share", share in 0.94..0.98)
    }

    @Test fun abbreviationLengthOptionMapsToTwoToSix() {
        val g = gen(); g.mode = CwGenerator.Mode.ABBREVS
        g.abbrevLengthMax = 2          // option 2 -> max length 3
        repeat(500) { assertTrue(g.nextContent().length <= 3) }
    }
}
