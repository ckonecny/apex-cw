package at.oe1cko.nextcwtrainer

import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * Native CW playback engine.
 * Converts text → timed dit/dah sequences, drives CwAudioNative directly.
 * No MethodChannel in the playback hot path.
 */
/** Timing jitter ("bad fist") of the other station, 0..1; CwTonePlugin implements it. */
interface GenTone {
    val jitter: Float
}

/** Where generated CW goes. The default is the native audio engine; tests record it. */
interface GenOut {
    /** Starts a new playback: whatever is queued or playing is dropped. */
    fun setKeyEpoch(epoch: Int)
    /** Queues one tone or pause; false if the queue is full. */
    fun enqueueKey(epoch: Int, on: Boolean, ms: Int): Boolean
    /** Silence until [ms] have passed since the previous playback's last sample. */
    fun enqueueIdleGap(epoch: Int, ms: Int): Boolean
    /** How much of this epoch's queue has been rendered so far; -1 before it has started. */
    fun keyPlayedMs(epoch: Int): Long
    fun setRx(on: Boolean)
}

object NativeGenOut : GenOut {
    override fun setKeyEpoch(epoch: Int) = CwAudioNative.setKeyEpoch(epoch)
    override fun enqueueKey(epoch: Int, on: Boolean, ms: Int) = CwAudioNative.enqueueKey(epoch, on, ms)
    override fun enqueueIdleGap(epoch: Int, ms: Int) = CwAudioNative.enqueueIdleGap(epoch, ms)
    override fun keyPlayedMs(epoch: Int) = CwAudioNative.keyPlayedMs(epoch)
    override fun setRx(on: Boolean) = CwAudioNative.setRx(on)
}

class CwGenerator(
    private val tone: GenTone,
    private val out: GenOut = NativeGenOut,
    // Sleeps for the given milliseconds; tests replace it with a virtual clock.
    private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
    // Reads a bundled Flutter asset ("assets/words/en.txt") as text, null if missing.
    // Random source; tests pass a seeded one.
    private val rng: Random = Random.Default,
    // Keep this the LAST parameter: MainActivity passes it as a trailing lambda.
    private val readAsset: (String) -> String? = { null },
) {

    // ── Content modes ─────────────────────────────────────────────────────────
    enum class Mode {
        RANDOM_CHARS,   // random 5-character groups from active Koch set
        WORDS,          // common English words
        CALLSIGNS,      // random callsigns
        MIXED,          // words + abbreviations
        PRACTICE_SET,   // uniform random draw from practiceChars only (M32 "Practice Set")
        ABBREVS         // CW abbreviations only (M32 "CW Abbrevs") — appended, not inserted,
                         // so existing stored mode indices (WORDS=1, CALLSIGNS=2, ...) don't shift
    }

    // ── Config ─────────────────────────────────────────────────────────────────
    @Volatile var wpm: Int = 20
    @Volatile var kochLevel: Int = 5          // how many Koch chars are active (2..kochChars.size)
    @Volatile var mode: Mode = Mode.RANDOM_CHARS
    @Volatile var farnsworthWpm: Int = 0      // 0 = disabled; >0 = letter speed stays wpm, spacing uses this

    // Extended settings
    // Matches the real M32 preferences exactly: absolute gap length in dits
    // (MorsePreferences.cpp: Interchar Spc 3..45 default 3, InterWord Spc 6..105 default 7)
    // — NOT a multiplier.
    @Volatile var interCharSpace: Int = 3     // total inter-character gap, in dits
    @Volatile var interWordSpace: Int = 7     // total inter-word gap, in dits
    @Volatile var eachWordTwice: Boolean = false
    @Volatile var groupLength: Int = 5        // random char group length (minimum)
    @Volatile var groupLengthMax: Int = 0     // 0 = same as groupLength (fixed length)
    // "Random Groups" (M32 posRandomOption): which subset of the alphabet the
    // plain (non-Koch) Random Chars mode draws from. Ignored when kochActive —
    // Koch Trainer's Random always draws from the active Koch level instead,
    // exactly like getRandomChars()'s own kochActive branch in m32_v6.ino.
    @Volatile var randomOption: Int = 0
    @Volatile var wordLengthMax: Int = 0      // 0 = no filter
    @Volatile var wordLengthMin: Int = 0      // 0 = no filter
    @Volatile var wordLanguage: Int = 0       // 0 = English, 1 = German (bundled frequency lists)
    @Volatile var abbrevLengthMin: Int = 0    // real length, 0 = no filter
    @Volatile var stopAfterItem: Boolean = false  // Morserino "Stop<>Next": false=continue, true=stop after one item
    @Volatile var abbrevLengthMax: Int = 0    // 0 = no filter (M32 "Length Abbrev")
    @Volatile var maxWords: Int = 0           // 0 = unlimited (M32 "Max # of Words"); ignored when stopAfterItem is on

    // Set by the Koch Trainer screen only (matches the real device's "kochActive" flag,
    // toggled when entering Koch Trainer's own nested Generator/Echo submenus): filters
    // Words/Abbrevs/Mixed down to the active Koch level's character subset, exactly like
    // Koch::createWords()/createAbbr()/wordIsKoch(). Plain CW Generator never sets this.
    @Volatile var kochActive: Boolean = false

    // "Length Calls"/"Calls Region"/"Call Prefixes" — see CallsignData.randomCallsign() for
    // exact option-value semantics (they match the M32 preference values directly).
    @Volatile var callLengthOpt: Int = 0
    @Volatile var callRegionOpt: Int = 0
    @Volatile var callCommonOnly: Boolean = false

    // "Practice Set" pool (M32 posPracticeChars) + "Boost Practice" (posRandomBoost):
    // 0=Off, 1=Moderate, 2=Strong. Boost only affects RANDOM_CHARS (bounded rejection
    // sampling, exactly like Koch::getRandomChar() — redraw up to N times until a
    // Practice Set char comes up; 1 attempt = no boost).
    @Volatile var practiceChars: List<String> = emptyList()
    @Volatile var boostLevel: Int = 0

    // ── Callbacks (called on generator thread — use runOnUiThread for UI) ──────
    var onChar:    ((String) -> Unit)? = null   // each character/prosign played
    var onWord:    ((String) -> Unit)? = null   // each complete word
    var onDone:    ((Boolean) -> Unit)? = null  // playback finished; param = stopped because "Max # of Words" was reached
    var onWaiting: (() -> Unit)?       = null   // paused after a word, awaiting paddle choice (stopAfterItem)
    var onElement: ((Int, Boolean) -> Unit)? = null // element idx within the current char; true=key-down, false=key-up

    // Set true by the generator thread after a word when stopAfterItem is on; cleared by
    // choosePaddle(). Mirrors the real M32: dit=repeat word, dah=next word (see morseGenerator
    // case in m32_v6.ino — autoStop halt/repeatword/nextword).
    @Volatile var awaitingChoice = false
        private set
    @Volatile private var pendingRepeat = false

    // ── Koch order — settable from Dart (Koch Sequence: M32/LCWO/CW Academy/
    // LICW/Custom). Defaults to the M32 native order, 51 entries, verified
    // against MorsePreferences.h's morserinoKochChars. A prosign lesson step is
    // a bracketed token ("<KA>"), the same form randomCharsAlphabet uses, so
    // joining the drawn entries into a group plays it as one prosign.
    @Volatile var kochChars: List<String> = listOf(
        "M","K","R","S","U","A","P","T","L","O","W","I",".",
        "N","J","E","F","0","Y","V",",","G","5","/","Q","9",
        "Z","H","3","8","B","?","4","2","7","C","1","D","6","X","-","=",
        "<SK>","+","<AS>","<KN>","<KA>","<VE>","<BK>","@",":"
    )

    // ── Morse code table ──────────────────────────────────────────────────────
    private val morseTable: Map<String, String> = mapOf(
        "A" to ".-",   "B" to "-...", "C" to "-.-.", "D" to "-..",
        "E" to ".",    "F" to "..-.", "G" to "--.",  "H" to "....",
        "I" to "..",   "J" to ".---", "K" to "-.-",  "L" to ".-..",
        "M" to "--",   "N" to "-.",   "O" to "---",  "P" to ".--.",
        "Q" to "--.-", "R" to ".-.",  "S" to "...",  "T" to "-",
        "U" to "..-",  "V" to "...-", "W" to ".--",  "X" to "-..-",
        "Y" to "-.--", "Z" to "--..",
        "0" to "-----","1" to ".----","2" to "..---","3" to "...--",
        "4" to "....-","5" to ".....","6" to "-....","7" to "--...",
        "8" to "---..", "9" to "----.",
        "." to ".-.-.-","," to "--..--","?" to "..--..","/" to "-..-.",
        "-" to "-....-", "=" to "-...-", "+" to ".-.-.", "@" to ".--.-.", ":" to "---...",
        // Common prosigns stored as multi-char keys
        // Verified against the real device's pool[] bit patterns (m32_v6.ino), not
        // popular-but-wrong lore: <KA>/<CT> ("starting signal") is -.-.- and is a
        // DIFFERENT prosign from <KN> ("invite specific station"), which is -.--.
        // — these are commonly confused; this table was wrong here before.
        "AR" to ".-.-.", "SK" to "...-.-", "KN" to "-.--.", "KA" to "-.-.-",
        "BT" to "-...-",  "AS" to ".-...",  "VE" to "...-.", "BK" to "-...-.-",
        "HH" to "........", "SOS" to "...---...",
        // German umlauts and the historic CH (----), as in the decoder tree.
        // Only the Morse tree plays them; Own Text flattens ä→AE etc. before
        // the text reaches the generator. CH needs the explicit <CH> form.
        "Ä" to ".-.-", "Ö" to "---.", "Ü" to "..--", "CH" to "----"
    )

    // ── Word lists ─────────────────────────────────────────────────────────────
    // Real CW abbreviation list (245 entries) — ported from abbrev.h, not hand-typed.
    private val abbreviations = listOf(
        "CONGRATS", "OUTPUT", "AWARD", "CONDS", "CONDX", "CUAGN", "ELBUG", "EXCUS", 
        "OSCAR", "UNLIS", "WATTS", "AWDH", "AWDS", "BCNU", "BURO", "CALL", "DIFF", "FONE", 
        "FREQ", "IARU", "INFO", "INPT", "MESZ", "MINS", "PSED", "RCVD", "RPRT", "RTTY", 
        "SASE", "SIGS", "SKED", "SSTV", "SURE", "TEMP", "TEST", "VERT", "WTTS", "XCUS", 
        "XCVR", "XMAS", "XTAL", "ABT", "ADR", "AGC", "AGN", "ALC", "ANS", "ANT", "ATV", 
        "AVC", "BCI", "BFO", "BPM", "BTR", "BTW", "BUG", "CFM", "CUL", "DWN", "FER", 
        "FRD", "FWD", "GND", "GUD", "HAM", "HPE", "HRD", "HRS", "HVY", "IRC", "ITU", 
        "KHZ", "LBR", "LID", "LIS", "LNG", "LOC", "LOG", "LSB", "LUF", "MEZ", "MGR", 
        "MHZ", "MIN", "MNI", "MOD", "MSG", "MTR", "MUF", "NET", "NIL", "OSC", "PEP", 
        "PSE", "PWR", "QAZ", "QRA", "QRB", "QRG", "QRL", "QRM", "QRN", "QRO", "QRP", 
        "QRQ", "QRS", "QRT", "QRU", "QRV", "QRX", "QRZ", "QSB", "QSK", "QSL", "QSO", 
        "QSP", "QST", "QSY", "QSZ", "QTC", "QTH", "QTR", "REF", "RFI", "RIG", "RPT", 
        "RST", "SHF", "SRI", "SSB", "STN", "SWL", "SWR", "TIA", "TKS", "TNX", "TRX", 
        "TVI", "UFB", "UHF", "UKW", "USB", "UTC", "VFO", "VHF", "VLN", "WID", "WKD", 
        "WKG", "WPM", "XYL", "33", "44", "55", "72", "73", "88", "99", "AA", "AB", "AC", 
        "AF", "AM", "AM", "BC", "BD", "BK", "B4", "CL", "CQ", "CU", "CW", "DB", "DC", 
        "DE", "DR", "DX", "EE", "EL", "ES", "FB", "FM", "FR", "GA", "GB", "GD", "GD", 
        "GE", "GL", "GM", "GN", "GP", "GS", "GT", "HF", "HI", "HR", "HV", "HW", "IF", 
        "II", "KM", "KW", "KY", "LF", "LP", "LW", "MA", "MM", "MY", "NF", "NO", "NR", 
        "NR", "NW", "OK", "OM", "OP", "OW", "PA", "PM", "PX", "RE", "RF", "RX", "SN", 
        "SP", "TU", "TX", "UP", "UR", "VL", "VY", "WL", "WX", "YL", "I", "K", "N", "R", 
        "T", "U", "V", "W", "Z"
    )

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    private var thread: Thread? = null
    @Volatile var running = false
        private set

    // Bumped on every stop()/start()/playOne() call. A thread only fires its
    // callbacks (onWord/onChar/onWaiting/onDone) while its OWN snapshot still
    // equals the live counter — once stop() bumps it, an already-interrupted
    // thread's still-in-flight finally block is silenced instead of firing a
    // stale event into whatever session started next. Without this, a delayed
    // onDone from a just-stopped generatorLoop() could arrive a few
    // milliseconds into the NEXT session and get mistaken for that session's
    // own completion (e.g. the start marker's playOne() completing before it
    // actually played, or the new session ending itself right after start) —
    // found by tracing a real, intermittent repro via logcat.
    @Volatile private var generation = 0

    /**
     * Play a single string (for Echo Trainer). Calls onDone when finished.
     * With [afterWordGap] it starts exactly one word gap after the end of the
     * previous playback, however late this call arrives within that gap.
     */
    fun playOne(text: String, afterWordGap: Boolean = false) {
        if (running) return
        val t = newTrack(++generation)
        running = true
        out.setRx(true)
        thread = Thread({
            try {
                // trailingGap=false: skip the inter-character gap after the LAST
                // character too — playWord()'s default trailing gap exists to
                // space this word from the next one in a continuous sequence,
                // which doesn't apply to a standalone playOne() call. Without
                // this, onDone fired ~(interCharSpace-1) dits after the last
                // beep for no reason — audible, and worse at low WPM (Echo
                // Trainer / Learn New Char / Preview) — before the operator was
                // allowed to key their echo. Now onDone fires right after the
                // last element's own natural key-up.
                if (afterWordGap) out.enqueueIdleGap(t.epoch, wordGapMs())
                playWord(text, t, trailingGap = false)
                drain(t)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } finally {
                finishPlayback(t)
            }
        }, "cw-gen-one").also { it.isDaemon = true; it.start() }
    }

    /** The full word and abbreviation lists, for Morsel's own Koch/length pool. */
    fun wordLists(): Map<String, List<String>> =
        mapOf("words" to weightedWords(0).words, "abbrevs" to abbreviations)

    /**
     * Plays raw dit/dah patterns (e.g. ".-", "-...") one per character, with
     * standard inter-character spacing — for WiFi Trx receive, where the
     * packet carries the exact elements (not text, so no prosign-key
     * ambiguity like "KA" = K+A vs <KA>). Calls onDone when finished.
     */
    fun playPatterns(patterns: List<String>) {
        if (running) return
        val t = newTrack(++generation)
        running = true
        out.setRx(true)
        thread = Thread({
            try {
                for ((i, p) in patterns.withIndex()) {
                    if (!running) break
                    playPattern(p, t)
                    if (i < patterns.size - 1) key(t, false, jitterGap(ditMs() * interCharSpace, hesitate = true))
                }
                drain(t)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } finally {
                finishPlayback(t)
            }
        }, "cw-gen-patterns").also { it.isDaemon = true; it.start() }
    }

    private fun playPattern(morse: String, t: Track) {
        for ((idx, sym) in morse.withIndex()) {
            if (!running) break
            key(t, true, jitterTone(sym == '.'))
            if (idx < morse.length - 1) key(t, false, jitterGap(ditMs()))
        }
    }

    fun start() {
        if (running) return
        val t = newTrack(++generation)
        running = true
        out.setRx(true)
        thread = Thread({ generatorLoop(t) }, "cw-generator").also {
            it.isDaemon = true; it.start()
        }
    }

    fun stop() {
        generation++
        running = false
        thread?.interrupt()
        out.setKeyEpoch(nextEpoch())
        out.setRx(false)
    }

    /** Called from a dit/dah key press while awaitingChoice: dit(repeat=true)=same word, dah(repeat=false)=next word. */
    fun choosePaddle(repeat: Boolean) {
        if (!awaitingChoice) return
        pendingRepeat = repeat
        awaitingChoice = false
    }

    // ── Main loop ─────────────────────────────────────────────────────────────
    private fun generatorLoop(t: Track) {
        var stoppedByMaxWords = false
        try {
            var lastText: String? = null
            var repeatNext = false
            var wordCount = 0
            while (running) {
                val text = if (repeatNext && lastText != null) lastText!! else nextContent()
                lastText = text
                repeatNext = false
                wordCount++

                playWord(text, t)
                if (eachWordTwice && running) {
                    key(t, false, jitterGap(ditMs() * wordGapExtra()))
                    playWord(text, t)
                }

                if (!running) break

                if (stopAfterItem) {
                    // Pause and wait for the operator's paddle choice (dit=repeat, dah=next),
                    // exactly like the real device's autoStop "halt" state.
                    drain(t)
                    awaitingChoice = true
                    if (t.gen == generation) onWaiting?.invoke()
                    while (awaitingChoice && running) Thread.sleep(20)
                    repeatNext = pendingRepeat
                } else if (maxWords > 0 && wordCount >= maxWords) {
                    // "Max # of Words": stops the generator, like the real device's
                    // maxSequence limit — not applied together with Stop<Next>Rep,
                    // matching "no maxSequence in autostop mode".
                    drain(t)
                    if (t.gen == generation) running = false
                    stoppedByMaxWords = true
                    break
                } else {
                    key(t, false, jitterGap(ditMs() * wordGapExtra()))
                }
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            awaitingChoice = false
            if (t.gen == generation) { out.setRx(false); onDone?.invoke(stoppedByMaxWords) }
        }
    }

    // ── Content generation ────────────────────────────────────────────────────
    // Public: lets other callers (e.g. Echo Trainer) fetch a piece of generated
    // content using this generator's config without starting playback.
    fun nextContent(): String {
        return when (mode) {
            Mode.RANDOM_CHARS -> randomCharGroup()
            Mode.WORDS        -> randomWord()
            Mode.CALLSIGNS    -> randomCallsign()
            // Koch Trainer's Mixed is a 3-way split (word/abbrev/random-char-group),
            // matching KOCH_MIXED exactly; plain Mixed stays word/abbrev only.
            Mode.MIXED        -> if (kochActive) kochMixedContent() else mixedContent()
            Mode.PRACTICE_SET -> randomPracticeGroup()
            Mode.ABBREVS      -> randomAbbrev()
        }
    }

    // Plain MIXED, as in fetchNewWord(): one of four, equally likely — a word,
    // an abbreviation, a call sign, or a single punctuation mark / prosign
    // (getRandomChars(1, OPT_PUNCTPRO)).
    private fun mixedContent(): String = when (rng.nextInt(4)) {
        0 -> randomWord()
        1 -> randomAbbrev()
        2 -> randomCallsign()
        else -> randomPoolChars(1, option = 7)
    }

    private fun kochMixedContent(): String = when (rng.nextInt(3)) {
        0 -> randomWord()
        1 -> randomAbbrev()
        else -> randomCharGroup()
    }

    // Boost Practice attempt counts, matching MorsePreferences.cpp's practiceBoostAttempts()
    // exactly: {Off, Moderate, Strong} -> {1, 3, 8}. 1 = no boost (accept the first draw).
    private fun boostAttempts(): Int {
        if (boostLevel <= 0 || practiceChars.isEmpty()) return 1
        return intArrayOf(1, 3, 8)[boostLevel.coerceIn(0, 2)]
    }

    // Group length: fixed when min == max, otherwise drawn anew for every
    // group, so the listener can't tell whether a group is over.
    private fun drawGroupLength(lo: Int, hi: Int): Int {
        val a = lo.coerceIn(1, 8)
        val b = (if (groupLengthMax > 0) groupLengthMax else lo).coerceIn(1, 8)
        return if (a >= b) a else rng.nextInt(a, b + 1)
    }

    private fun randomCharGroup(): String {
        val len = drawGroupLength(groupLength.coerceIn(1, 8), groupLengthMax)
        return if (kochActive) randomKochChars(len) else randomPoolChars(len)
    }

    // Master alphabet for "Random Groups" (mirrors CWchars[0..50] in m32_v6.ino,
    // minus the trailing äöüH it never actually draws from). The six single-
    // letter prosign codes there (S,A,N,K,E,B at indices 45..50) are
    // represented here by their bracketed mnemonics ("<AS>","<KA>",...) —
    // the same form the firmware's cleanUpProSigns() displays. playWord()
    // only plays a prosign for an explicit <XX> token, so letter pairs in
    // words/abbrevs/groups ("START", "AS", "KAS") stay plain letters.
    private val randomCharsAlphabet: List<String> =
        "abcdefghijklmnopqrstuvwxyz0123456789.,:-/=?@+".map { it.toString() } +
        listOf("<AS>", "<KA>", "<KN>", "<SK>", "<VE>", "<BK>")

    // "Random Groups" pool ranges into randomCharsAlphabet — matches
    // getRandomChars()'s option table in m32_v6.ino exactly (half-open [s,e)
    // there becomes an inclusive s..(e-1) range here).
    private fun randomGroupsRange(option: Int): IntRange = when (option) {
        1 -> 0..25    // Alpha
        2 -> 26..35   // Num
        3 -> 36..44   // Punct
        4 -> 44..50   // Pro
        5 -> 0..35    // Alpha+Num
        6 -> 26..44   // Num+Punct
        7 -> 36..50   // Punct+Pro
        8 -> 0..44    // Alpha+Num+Punct
        9 -> 26..50   // Num+Punct+Pro
        else -> 0..50 // All
    }

    // Non-Koch Random Chars with Boost Practice: an exact WEIGHTED draw, as in
    // getRandomChars() — characters of the Practice Set count 3x (Moderate) or
    // 8x (Strong), all others 1x, within the chosen Random Groups range. This
    // is deliberately not the redraw scheme of the Koch path (boostAttempts);
    // the firmware warns that the two are not calibrated against each other.
    private fun randomPoolChars(len: Int, option: Int = randomOption): String {
        val range = randomGroupsRange(option)
        val mult = if (boostLevel in 1..2 && practiceChars.isNotEmpty()) intArrayOf(3, 8)[boostLevel - 1] else 1
        val weight = IntArray(range.count()) { i ->
            if (mult > 1 && randomCharsAlphabet[range.first + i] in practiceChars) mult else 1
        }
        val total = weight.sum()
        return (1..len).joinToString("") {
            var roll = rng.nextInt(total)
            var j = 0
            while (roll >= weight[j]) { roll -= weight[j]; j++ }
            randomCharsAlphabet[range.first + j]
        }
    }

    private fun activeKochSet(): List<String> = kochChars.take(kochLevel.coerceIn(2, kochChars.size))

    // Mirrors Koch::getRandomChar()'s weighting exactly (MorsePreferences.cpp,
    // "in Koch mode, we generate the last third of the chars learned a bit
    // more often"): 2-in-3 draws come from the whole active set, 1-in-3 are
    // restricted to its last third — which is where the most recently
    // unlocked (least-practiced) character always sits, so it comes up
    // disproportionately more than long-mastered ones without a separate
    // boost mechanism. This was previously a uniform draw here, diverging
    // from the firmware.
    private fun weightedKochChar(active: List<String>): String {
        val endk = active.size
        return if (rng.nextInt(3) != 0) active[rng.nextInt(endk)]
        else active[rng.nextInt(2 * endk / 3, endk)]
    }

    private fun randomKochChars(len: Int): String {
        val active = activeKochSet()
        val tries  = boostAttempts()
        return (1..len).map {
            var c = weightedKochChar(active)
            var t = 1
            while (t < tries && c !in practiceChars) { c = weightedKochChar(active); t++ }
            c
        }.joinToString("")
    }

    // "Practice Set" content mode: draws uniformly from practiceChars only (not
    // Koch-level-limited, not boosted — matches getRandomChars()'s usePracticeChars path).
    private fun randomPracticeGroup(): String {
        if (practiceChars.isEmpty()) return randomCharGroup()
        val len = drawGroupLength(groupLength, groupLengthMax).let {
            if (wordLengthMax > 0) minOf(it, wordLengthMax) else it
        }.coerceIn(1, 8)
        return (1..len).map { practiceChars.random(rng) }.joinToString("")
    }

    // A word/abbrev "qualifies" for the active Koch level iff every one of its
    // characters is among the first kochLevel entries of the sequence — mirrors
    // Koch::wordIsKoch() (highest Koch index used <= kochLevel).
    private fun kochQualifies(text: String): Boolean {
        val active = activeKochSet().toSet()
        return text.all { it.toString() in active }
    }

    // Frequency-weighted word lists (assets/words/{en,de}.txt, "word weight" per
    // line), loaded once per language. An unreadable asset gives an empty list
    // (the callers then draw single characters).
    private class WeightedWords(val words: List<String>, val weights: IntArray)

    private val weightedCache = HashMap<Int, WeightedWords>()

    private fun weightedWords(lang: Int = wordLanguage): WeightedWords = synchronized(weightedCache) {
        weightedCache.getOrPut(lang) {
            val name = if (lang == 1) "de" else "en"
            val ws = ArrayList<String>()
            val wt = ArrayList<Int>()
            readAsset("assets/words/$name.txt")?.lineSequence()?.forEach { line ->
                val parts = line.trim().split(' ')
                val w = parts.getOrNull(0).orEmpty()
                val c = parts.getOrNull(1)?.toIntOrNull()
                if (w.isNotEmpty() && c != null && c > 0) { ws.add(w.uppercase()); wt.add(c) }
            }
            WeightedWords(ws, wt.toIntArray())
        }
    }

    /** Weighted draw from [indices] of [list] (cumulative sum + binary search). */
    private fun pickWeighted(list: WeightedWords, indices: List<Int>): String {
        val cum = LongArray(indices.size)
        var total = 0L
        for ((k, i) in indices.withIndex()) { total += list.weights[i]; cum[k] = total }
        val r = rng.nextLong(total)
        var lo = 0; var hi = cum.size - 1
        while (lo < hi) { val mid = (lo + hi) ushr 1; if (cum[mid] > r) hi = mid else lo = mid + 1 }
        return list.words[indices[lo]]
    }

    private fun randomWord(): String {
        val list = weightedWords()
        if (list.words.isEmpty()) return randomKochChars(1)
        var pool = list.words.indices.filter {
            val len = list.words[it].length
            (wordLengthMax <= 0 || len <= wordLengthMax) && len >= wordLengthMin
        }
        if (kochActive) {
            pool = pool.filter { kochQualifies(list.words[it]) }
            // No qualifying word at this (early) Koch level: fall back to a single
            // character drill, exactly like Koch::getRandomWord() does.
            if (pool.isEmpty()) return randomKochChars(1)
        }
        return pickWeighted(list, if (pool.isEmpty()) list.words.indices.toList() else pool)
    }

    // abbrevLengthMax uses the same option encoding as the M32 "Length Abbrev" preference
    // (0=unlimited, 1..5 => max length 2..6 — see getRandomAbbrev()'s ++maxLength).
    private fun randomAbbrev(): String {
        val maxLen = if (abbrevLengthMax in 1..5) abbrevLengthMax + 1 else 0
        var pool = abbreviations.filter { (maxLen <= 0 || it.length <= maxLen) && it.length >= abbrevLengthMin }
        if (kochActive) {
            pool = pool.filter { kochQualifies(it) }
            if (pool.isEmpty()) return randomKochChars(1)
        }
        return (if (pool.isEmpty()) abbreviations else pool).random(rng)
    }

    private fun randomCallsign(): String =
        CallsignData.randomCallsign(callLengthOpt, callRegionOpt, callCommonOnly)

    // ── Playback ──────────────────────────────────────────────────────────────
    // trailingGap=false (used by playOne(), see below) skips the inter-character
    // gap after the WORD's very last character — that gap only exists to space
    // this word from whatever plays next, which for a standalone single-word
    // playback is nothing, so keeping it just adds dead time before onDone.
    private fun playWord(text: String, t: Track, trailingGap: Boolean = true) {
        at(t) { onWord?.invoke(text) }
        val upper = text.uppercase()
        // A prosign must be written as an explicit <XX> token; a plain letter
        // pair is always two letters (START used to play as S T <AR> T, the
        // word AS and the abbreviation BK as prosigns).
        var i = 0
        while (i < upper.length && running) {
            val close = if (upper[i] == '<') upper.indexOf('>', i) else -1
            val prosign = if (close > i) upper.substring(i + 1, close) else null
            val isProsign = prosign != null && prosign.length >= 2 && morseTable.containsKey(prosign)
            val nextIndex = if (isProsign) close + 1 else i + 1
            val isLastToken = nextIndex >= upper.length
            if (isProsign) {
                playChar(prosign!!, t, trailingGap || !isLastToken)
            } else {
                val c = upper[i].toString()
                if (c == " ") {
                    key(t, false, jitterGap(ditMs() * wordGapExtra(), hesitate = true))
                } else {
                    playChar(c, t, trailingGap || !isLastToken)
                }
            }
            i = nextIndex
        }
    }

    /** Test hook: plays one word synchronously on the calling thread. */
    internal fun playWordNow(text: String, trailingGap: Boolean = true, afterWordGap: Boolean = false) {
        running = true
        val t = newTrack(generation)
        try {
            if (afterWordGap) out.enqueueIdleGap(t.epoch, wordGapMs())
            playWord(text, t, trailingGap)
            drain(t)
        } finally { running = false }
    }

    private fun playChar(ch: String, t: Track, withTrailingGap: Boolean = true) {
        val morse = morseTable[ch] ?: return
        for ((idx, sym) in morse.withIndex()) {
            if (!running) break
            at(t) { onElement?.invoke(idx, true) }
            key(t, true, jitterTone(sym == '.'))
            at(t) { onElement?.invoke(idx, false) }
            // inter-element gap (skip after last symbol — inter-char gap follows)
            if (idx < morse.length - 1) key(t, false, jitterGap(ditMs()))
        }
        // Fire only once the character has actually finished playing — matches the
        // real device's dispGeneratedChar(), called at KEY_DOWN→KEY_UP once keying
        // for that char is done, not when it starts.
        at(t) { onChar?.invoke(ch) }
        // Inter-character gap: Interchar Spc dits counted from the end of the last
        // tone (generateCW(): genTimer = interCharacterSpace). There is no
        // inter-element gap after the last element of a character (it was
        // once subtracted here as "already consumed", which made every
        // character gap, and with it every word gap, one dit too short).
        if (withTrailingGap) key(t, false, jitterGap(ditMs() * interCharSpace, hesitate = true))
    }

    // ── Keying queue ──────────────────────────────────────────────────────────
    // Tones and pauses go into a queue that the audio callback counts off in
    // samples (key_schedule.h), so their length no longer depends on when this
    // thread wakes up or on the size of the audio blocks. This thread only keeps
    // the queue LEAD_MS ahead; anything that happens "when the sound gets there"
    // (display callbacks, end of playback) waits for the played position.

    /** One playback, confined to its generator thread. */
    private class Track(val gen: Int, var epoch: Int) {
        var queuedMs = 0L                                     // total length queued so far
        val events = ArrayDeque<Pair<Long, () -> Unit>>()     // (queue position, action)
    }

    private var lastEpoch = 0

    @Synchronized private fun nextEpoch(): Int = ++lastEpoch

    private fun newTrack(gen: Int): Track {
        val epoch = nextEpoch()
        out.setKeyEpoch(epoch)
        return Track(gen, epoch)
    }

    private fun isCurrent(t: Track) = running && t.gen == generation

    // `running` belongs to the newest playback: a stopped thread reaching this
    // after the next playOne() has started must not end that one too.
    private fun finishPlayback(t: Track) {
        if (t.gen != generation) return
        running = false
        out.setRx(false)
        onDone?.invoke(false)
    }

    /** Runs [action] when playback reaches the current end of the queue. */
    private fun at(t: Track, action: () -> Unit) {
        t.events.addLast(t.queuedMs to { if (t.gen == generation) action() })
    }

    private fun key(t: Track, on: Boolean, ms: Int) {
        if (ms <= 0) return
        while (!out.enqueueKey(t.epoch, on, ms)) {
            if (!isCurrent(t)) return
            sleeper(POLL_MS)
        }
        t.queuedMs += ms
        pace(t, LEAD_MS)
    }

    /** Waits until everything queued has been played, and fires what is still due. */
    private fun drain(t: Track) {
        pace(t, 0)
        if (isCurrent(t)) fireEvents(t, t.queuedMs)
    }

    // Waits until at most [keepMs] of the queue is still unplayed. If the audio
    // stream stops moving (a route change that never recovers) the queue is
    // given up, so that stop() and onDone never depend on a working stream.
    private fun pace(t: Track, keepMs: Long) {
        var pos = out.keyPlayedMs(t.epoch)
        var last = pos
        var stalledMs = 0L
        fireEvents(t, pos)
        while (isCurrent(t) && t.queuedMs - maxOf(pos, 0L) > keepMs) {
            val waitMs = nextWakeMs(t, pos, keepMs)
            sleeper(waitMs)
            pos = out.keyPlayedMs(t.epoch)
            fireEvents(t, pos)
            if (pos != last) {
                last = pos
                stalledMs = 0
            } else {
                stalledMs += waitMs
                if (stalledMs >= STALL_MS) {
                    fireEvents(t, t.queuedMs)
                    t.epoch = nextEpoch()
                    out.setKeyEpoch(t.epoch)
                    t.queuedMs = 0
                    return
                }
            }
        }
    }

    // Sleeps only as long as nothing is due, so long playback with the screen
    // off doesn't wake this thread hundreds of times a second.
    private fun nextWakeMs(t: Track, pos: Long, keepMs: Long): Long {
        val played = maxOf(pos, 0L)
        val untilTopUp = t.queuedMs - played - keepMs
        val untilEvent = t.events.firstOrNull()?.let { it.first - played } ?: untilTopUp
        return minOf(untilTopUp, untilEvent).coerceIn(POLL_MS, MAX_WAIT_MS)
    }

    private fun fireEvents(t: Track, pos: Long) {
        while (t.events.isNotEmpty() && t.events.first().first <= pos) t.events.removeFirst().second()
    }

    // Extra dits needed after the inter-char gap to reach the full inter-word
    // gap, which the firmware computes in updateTimings() as
    // max(InterWord Spc, Interchar Spc + 4) dits, counted from the last tone.
    private fun wordGapExtra(): Int = maxOf(interWordSpace, interCharSpace + 4) - interCharSpace
    private fun wordGapMs(): Int = ditMs() * maxOf(interWordSpace, interCharSpace + 4)

    // ── Timing helpers ────────────────────────────────────────────────────────
    private fun ditMs()  = (1200.0 / wpm).roundToInt()
    private fun dahMs()  = ditMs() * 3

    // ── Interference: timing jitter ("bad fist") of the other station ────────
    // Level 0..1 from the interference settings (CwTonePlugin.jitter). Every
    // element and gap gets its own random factor, dahs also vary in their
    // dit:dah ratio, and at high levels a character gap occasionally
    // hesitates. At 0 the timing is exact. Only the other station's signal
    // goes through the generator; the user's own keying is never touched.
    private fun rnd() = rng.nextFloat() * 2f - 1f   // -1..1

    private fun jitterTone(dit: Boolean): Int {
        val j = tone.jitter
        val base = if (dit) ditMs() else dahMs()
        if (j <= 0f) return base
        // dahs additionally stray from the 3:1 ratio
        val ratio = if (dit) 1f else 1f + j * 0.25f * rnd()
        return (base * ratio * (1f + j * 0.35f * rnd())).roundToInt().coerceAtLeast(ditMs() / 3)
    }

    private fun jitterGap(ms: Int, hesitate: Boolean = false): Int {
        val j = tone.jitter
        if (j <= 0f || ms <= 0) return ms
        var v = ms * (1f + j * 0.5f * rnd())
        if (hesitate && rng.nextFloat() < j * 0.08f) v += ditMs() * (1 + rng.nextInt(2))
        return v.roundToInt().coerceAtLeast(1)
    }

    private companion object {
        const val LEAD_MS = 100L    // how far the queue stays ahead of the audio
        const val POLL_MS = 2L
        const val MAX_WAIT_MS = 20L
        const val STALL_MS = 1500L  // no audio progress for this long: stream is gone
    }
}
