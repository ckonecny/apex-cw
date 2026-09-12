package at.oe1wkl.morserino_mobile

import kotlin.math.roundToInt
import kotlin.random.Random

/**
 * Native CW playback engine.
 * Converts text → timed dit/dah sequences, drives CwAudioNative directly.
 * No MethodChannel in the playback hot path.
 */
class CwGenerator(private val tone: CwTonePlugin) {

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
    @Volatile var groupLength: Int = 5        // random char group length
    // "Random Groups" (M32 posRandomOption): which subset of the alphabet the
    // plain (non-Koch) Random Chars mode draws from. Ignored when kochActive —
    // Koch Trainer's Random always draws from the active Koch level instead,
    // exactly like getRandomChars()'s own kochActive branch in m32_v6.ino.
    @Volatile var randomOption: Int = 0
    @Volatile var wordLengthMax: Int = 0      // 0 = no filter
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

    // Set true by the generator thread after a word when stopAfterItem is on; cleared by
    // choosePaddle(). Mirrors the real M32: dit=repeat word, dah=next word (see morseGenerator
    // case in m32_v6.ino — autoStop halt/repeatword/nextword).
    @Volatile var awaitingChoice = false
        private set
    @Volatile private var pendingRepeat = false

    // ── Koch order — settable from Dart (Koch Sequence: M32/LCWO/CW Academy/
    // LICW/Custom). Defaults to the M32 native order, 45 chars, verified
    // against MorsePreferences.h's morserinoKochChars (the plain portion,
    // before its 6-char prosign tail — prosigns aren't individually
    // orderable Koch characters here yet).
    @Volatile var kochChars: List<String> = listOf(
        "M","K","R","S","U","A","P","T","L","O","W","I",".",
        "N","J","E","F","0","Y","V",",","G","5","/","Q","9",
        "Z","H","3","8","B","?","4","2","7","C","1","D","6","X","-","=","+","@",":"
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
        "HH" to "........"
    )

    // ── Word lists ─────────────────────────────────────────────────────────────
    // Real M32 word list (373 entries, up to 13 chars) — ported from english_words.h's
    // default (non-CONFIG_ENGLISH_OXFORD) words[] array, not hand-typed.
    private val words = listOf(
        "INTERNATIONAL", "UNIVERSITY", "GOVERNMENT", "INCLUDING", "FOLLOWING", "NATIONAL", 
        "AMERICAN", "RELEASED", "ALTHOUGH", "DISTRICT", "SENTENCE", "TOGETHER", 
        "CHILDREN", "MOUNTAIN", "BETWEEN", "HOWEVER", "THROUGH", "SEVERAL", "HISTORY", 
        "AGAINST", "BECAUSE", "LOCATED", "COMPANY", "GENERAL", "ANOTHER", "CENTURY", 
        "STATION", "BRITISH", "COLLEGE", "MEMBERS", "PICTURE", "COUNTRY", "THOUGHT", 
        "EXAMPLE", "DURING", "SCHOOL", "UNITED", "STATES", "BECAME", "BEFORE", "PEOPLE", 
        "SECOND", "CALLED", "SERIES", "NUMBER", "FAMILY", "COUNTY", "SYSTEM", "SEASON", 
        "PLAYED", "AROUND", "PUBLIC", "FORMER", "CAREER", "LITTLE", "DIFFER", "FOLLOW", 
        "CHANGE", "ANIMAL", "MOTHER", "FATHER", "SHOULD", "ANSWER", "ALWAYS", "LETTER", 
        "FRIEND", "WHICH", "FIRST", "THEIR", "AFTER", "OTHER", "THERE", "YEARS", "WOULD", 
        "WHERE", "LATER", "THESE", "ABOUT", "UNDER", "WORLD", "KNOWN", "WHILE", "STATE", 
        "THREE", "BEING", "EARLY", "SINCE", "UNTIL", "SOUTH", "NORTH", "MUSIC", "ALBUM", 
        "GROUP", "OFTEN", "THOSE", "HOUSE", "BEGAN", "COULD", "FOUND", "MAJOR", "RIVER", 
        "NAMED", "STILL", "PLACE", "LOCAL", "PARTY", "LARGE", "SMALL", "ALONG", "BASED", 
        "WRITE", "THING", "SOUND", "WATER", "ROUND", "EVERY", "GREAT", "THINK", "CAUSE", 
        "RIGHT", "SPELL", "LIGHT", "AGAIN", "POINT", "BUILD", "EARTH", "STAND", "STUDY", 
        "LEARN", "PLANT", "COVER", "NEVER", "CROSS", "START", "MIGHT", "STORY", "PRESS", 
        "CLOSE", "NIGHT", "WHITE", "BEGIN", "PAPER", "CARRY", "WATCH", "WITH", "THAT", 
        "FROM", "WERE", "THIS", "ALSO", "HAVE", "THEY", "BEEN", "WHEN", "INTO", "MORE", 
        "TIME", "MOST", "SOME", "ONLY", "OVER", "MANY", "SUCH", "USED", "CITY", "THEN", 
        "THAN", "MADE", "PART", "YEAR", "BOTH", "THEM", "NAME", "AREA", "WELL", "WILL", 
        "HIGH", "BORN", "WORK", "TOWN", "FILM", "TEAM", "EACH", "LIFE", "SAME", "GAME", 
        "FOUR", "WEST", "LINE", "LIKE", "VERY", "JOHN", "HOME", "BACK", "BAND", "SHOW", 
        "YORK", "EVEN", "MUCH", "EAST", "WHAT", "YOUR", "WORD", "SAID", "LONG", "MAKE", 
        "LOOK", "COME", "KNOW", "CALL", "DOWN", "SIDE", "FIND", "TAKE", "LIVE", "CAME", 
        "GOOD", "GIVE", "JUST", "FORM", "HELP", "TURN", "MEAN", "MOVE", "DOES", "TELL", 
        "WANT", "PLAY", "READ", "HAND", "PORT", "LAND", "HERE", "MUST", "WENT", "KIND", 
        "NEED", "NEAR", "SELF", "HEAD", "PAGE", "GROW", "FOOD", "KEEP", "LAST", "DOOR", 
        "TREE", "HARD", "DRAW", "LEFT", "LATE", "REAL", "STOP", "OPEN", "SEEM", "NEXT", 
        "WALK", "EASE", "MARK", "BOOK", "MILE", "FEET", "CARE", "TOOK", "RAIN", "ROOM", 
        "IDEA", "FISH", "ONCE", "BASE", "HEAR", "SURE", "FACE", "WOOD", "MAIN", "THE", 
        "AND", "WAS", "FOR", "HIS", "ARE", "HAS", "HAD", "ONE", "NOT", "BUT", "ITS", 
        "NEW", "WHO", "HER", "TWO", "SHE", "ALL", "CAN", "MAY", "OUT", "HIM", "WAR", 
        "AGE", "NOW", "USE", "ANY", "END", "DAY", "DID", "OWN", "DUE", "WON", "SUM", 
        "USA", "YOU", "HOT", "HOW", "WAY", "SEE", "MAN", "OUR", "SAY", "LOW", "BOY", 
        "OLD", "TOO", "SET", "AIR", "PUT", "ADD", "BIG", "ACT", "WHY", "ASK", "MEN", 
        "OFF", "TRY", "SUN", "LET", "EYE", "SAW", "FAR", "SEA", "RUN", "FEW", "GOT", 
        "CAR", "EAT", "CUT", "OF", "KM", "MR", "US", "IN", "TO", "IS", "AS", "ON", "BY", 
        "HE", "AT", "IT", "AN", "OR", "BE", "UP", "NO", "SO", "IF", "WE", "DO", "GO", 
        "MY", "ME", "A", "I", "M"
    )

    // Real CW abbreviation list (244 entries) — ported from abbrev.h, not hand-typed.
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
        "T", "U", "V", "W"
    )

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    private var thread: Thread? = null
    @Volatile var running = false
        private set
    @Volatile private var paused  = false

    /** Play a single string (for Echo Trainer). Calls onDone when finished. */
    fun playOne(text: String) {
        if (running) return
        running = true
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
                playWord(text, trailingGap = false)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } finally {
                running = false
                CwAudioNative.setPlaying(false)
                onDone?.invoke(false)
            }
        }, "cw-gen-one").also { it.isDaemon = true; it.start() }
    }

    fun start() {
        if (running) return
        running = true
        thread = Thread({ generatorLoop() }, "cw-generator").also {
            it.isDaemon = true; it.start()
        }
    }

    fun stop() {
        running = false
        paused  = false
        thread?.interrupt()
        CwAudioNative.setPlaying(false)
    }

    fun pause()  { paused = true }
    fun resume() { paused = false }

    /** Called from a dit/dah key press while awaitingChoice: dit(repeat=true)=same word, dah(repeat=false)=next word. */
    fun choosePaddle(repeat: Boolean) {
        if (!awaitingChoice) return
        pendingRepeat = repeat
        awaitingChoice = false
    }

    // ── Main loop ─────────────────────────────────────────────────────────────
    private fun generatorLoop() {
        var stoppedByMaxWords = false
        try {
            var lastText: String? = null
            var repeatNext = false
            var wordCount = 0
            while (running) {
                while (paused && running) Thread.sleep(50)
                if (!running) break

                val text = if (repeatNext && lastText != null) lastText!! else nextContent()
                lastText = text
                repeatNext = false
                wordCount++

                playWord(text)
                if (eachWordTwice && running) {
                    sleepMs(ditMs() * wordGapExtra())
                    playWord(text)
                }

                if (!running) break

                if (stopAfterItem) {
                    // Pause and wait for the operator's paddle choice (dit=repeat, dah=next),
                    // exactly like the real device's autoStop "halt" state.
                    awaitingChoice = true
                    onWaiting?.invoke()
                    while (awaitingChoice && running) Thread.sleep(20)
                    repeatNext = pendingRepeat
                } else if (maxWords > 0 && wordCount >= maxWords) {
                    // "Max # of Words": stops the generator, like the real device's
                    // maxSequence limit — not applied together with Stop<Next>Rep,
                    // matching "no maxSequence in autostop mode".
                    running = false
                    stoppedByMaxWords = true
                    break
                } else {
                    sleepMs(ditMs() * wordGapExtra())
                }
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            awaitingChoice = false
            CwAudioNative.setPlaying(false)
            onDone?.invoke(stoppedByMaxWords)
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
            Mode.MIXED        -> if (kochActive) kochMixedContent()
                                  else if (Random.nextBoolean()) randomWord() else randomAbbrev()
            Mode.PRACTICE_SET -> randomPracticeGroup()
            Mode.ABBREVS      -> randomAbbrev()
        }
    }

    private fun kochMixedContent(): String = when (Random.nextInt(3)) {
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

    private fun randomCharGroup(): String {
        val len = groupLength.coerceIn(2, 8)
        return if (kochActive) randomKochChars(len) else randomPoolChars(len)
    }

    // Master alphabet for "Random Groups" (mirrors CWchars[0..50] in m32_v6.ino,
    // minus the trailing äöüH it never actually draws from). The six single-
    // letter prosign codes there (S,A,N,K,E,B at indices 45..50) are
    // represented here by their two-letter mnemonics ("AS","KA","KN","SK",
    // "VE","BK") instead: playWord() upper-cases all generated text before
    // parsing, so — unlike the firmware, which tells a prosign code from the
    // real letter by case — this app can only recognize a prosign via its
    // two-character lookahead (see morseTable), the same convention already
    // used by the start/end session markers.
    private val randomCharsAlphabet: List<String> =
        "abcdefghijklmnopqrstuvwxyz0123456789.,:-/=?@+".map { it.toString() } +
        listOf("AS", "KA", "KN", "SK", "VE", "BK")

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

    private fun randomPoolChars(len: Int): String {
        val range = randomGroupsRange(randomOption)
        val tries = boostAttempts()
        return (1..len).joinToString("") {
            var idx = range.random()
            var t = 1
            while (t < tries && randomCharsAlphabet[idx] !in practiceChars) { idx = range.random(); t++ }
            randomCharsAlphabet[idx]
        }
    }

    private fun activeKochSet(): List<String> = kochChars.take(kochLevel.coerceIn(2, kochChars.size))

    private fun randomKochChars(len: Int): String {
        val active = activeKochSet()
        val tries  = boostAttempts()
        return (1..len).map {
            var c = active.random()
            var t = 1
            while (t < tries && c !in practiceChars) { c = active.random(); t++ }
            c
        }.joinToString("")
    }

    // "Practice Set" content mode: draws uniformly from practiceChars only (not
    // Koch-level-limited, not boosted — matches getRandomChars()'s usePracticeChars path).
    private fun randomPracticeGroup(): String {
        if (practiceChars.isEmpty()) return randomCharGroup()
        val len = groupLength.coerceIn(2, 8)
        return (1..len).map { practiceChars.random() }.joinToString("")
    }

    // A word/abbrev "qualifies" for the active Koch level iff every one of its
    // characters is among the first kochLevel entries of the sequence — mirrors
    // Koch::wordIsKoch() (highest Koch index used <= kochLevel).
    private fun kochQualifies(text: String): Boolean {
        val active = activeKochSet().toSet()
        return text.all { it.toString() in active }
    }

    private fun randomWord(): String {
        var pool = if (wordLengthMax > 0) words.filter { it.length <= wordLengthMax } else words
        if (kochActive) {
            pool = pool.filter { kochQualifies(it) }
            // No qualifying word at this (early) Koch level: fall back to a single
            // character drill, exactly like Koch::getRandomWord() does.
            if (pool.isEmpty()) return randomKochChars(1)
        }
        return (if (pool.isEmpty()) words else pool).random()
    }

    // abbrevLengthMax uses the same option encoding as the M32 "Length Abbrev" preference
    // (0=unlimited, 1..5 => max length 2..6 — see getRandomAbbrev()'s ++maxLength).
    private fun randomAbbrev(): String {
        val maxLen = if (abbrevLengthMax in 1..5) abbrevLengthMax + 1 else 0
        var pool = if (maxLen > 0) abbreviations.filter { it.length <= maxLen } else abbreviations
        if (kochActive) {
            pool = pool.filter { kochQualifies(it) }
            if (pool.isEmpty()) return randomKochChars(1)
        }
        return (if (pool.isEmpty()) abbreviations else pool).random()
    }

    private fun randomCallsign(): String =
        CallsignData.randomCallsign(callLengthOpt, callRegionOpt, callCommonOnly)

    // ── Playback ──────────────────────────────────────────────────────────────
    // trailingGap=false (used by playOne(), see below) skips the inter-character
    // gap after the WORD's very last character — that gap only exists to space
    // this word from whatever plays next, which for a standalone single-word
    // playback is nothing, so keeping it just adds dead time before onDone.
    private fun playWord(text: String, trailingGap: Boolean = true) {
        onWord?.invoke(text)
        val upper = text.uppercase()
        var i = 0
        while (i < upper.length && running) {
            // Check for two-char prosigns
            val twoChar = if (i + 1 < upper.length) upper.substring(i, i + 2) else null
            val consumesTwo = twoChar != null && morseTable.containsKey(twoChar)
            val nextIndex = i + (if (consumesTwo) 2 else 1)
            val isLastToken = nextIndex >= upper.length
            if (consumesTwo) {
                playChar(twoChar!!, trailingGap || !isLastToken)
            } else {
                val c = upper[i].toString()
                if (c == " ") {
                    sleepMs(ditMs() * wordGapExtra())
                } else {
                    playChar(c, trailingGap || !isLastToken)
                }
            }
            i = nextIndex
        }
    }

    private fun playChar(ch: String, withTrailingGap: Boolean = true) {
        val morse = morseTable[ch] ?: return
        for ((idx, sym) in morse.withIndex()) {
            if (!running) break
            val toneDur = if (sym == '.') ditMs() else dahMs()
            CwAudioNative.setPlaying(true)
            sleepMs(toneDur)
            CwAudioNative.setPlaying(false)
            // inter-element gap (skip after last symbol — inter-char gap follows)
            if (idx < morse.length - 1) sleepMs(ditMs())
        }
        // Fire only once the character has actually finished playing — matches the
        // real device's dispGeneratedChar(), called at KEY_DOWN→KEY_UP once keying
        // for that char is done, not when it starts.
        onChar?.invoke(ch)
        // inter-character gap: interCharSpace total dits; -1 because last inter-element already consumed 1 dit
        if (withTrailingGap) sleepMs(ditMs() * (interCharSpace - 1))
    }

    // Extra dits needed after inter-char to reach the full (absolute) inter-word gap
    private fun wordGapExtra(): Int = maxOf(1, interWordSpace - interCharSpace)

    // ── Timing helpers ────────────────────────────────────────────────────────
    private fun ditMs()  = (1200.0 / wpm).roundToInt()
    private fun dahMs()  = ditMs() * 3

    private fun sleepMs(ms: Int) {
        if (ms <= 0) return
        Thread.sleep(ms.toLong())
    }
}
