package at.oe1wkl.morserino_mobile

import kotlin.math.roundToInt

class CwKeyer(private val tone: CwTonePlugin) {

    enum class State { IDLE, KEY_START, DIT, DAH, INTER_ELEMENT }
    enum class Mode { IAMBIC_A, IAMBIC_B, ULTIMATIC, NON_SQUEEZE, STRAIGHT }

    @Volatile var wpm: Int = 20
    @Volatile var mode: Mode = Mode.IAMBIC_A

    // "CurtisB DitT%"/"CurtisB DahT%" (0-100, defaults 75/45 match the real
    // device's MorsePreferences.cpp): how far into the CURRENT element,
    // as a percentage of its length, the keyer starts looking for the
    // OPPOSITE paddle in Iambic B / Ultimatic mode — matches m32_v6.ino's
    // KEYED-state curtistimer (2 + elementLength*value/100 ms), which polls
    // only the opposite paddle from that point until the element ends,
    // letting the operator "look ahead" into the next element earlier or
    // later than the element's own boundary.
    @Volatile var curtisBDitTiming: Int = 75
    @Volatile var curtisBDahTiming: Int = 45

    // "AutoChar Spc" (M32 posACS, default 0=off; 1/2/3 -> 2/3/4 dits): once a
    // character completes, the keyer ignores a new paddle press until this
    // many dit-lengths have passed — a training aid that enforces a minimum
    // gap between characters. Matches m32_v6.ino's acsTimer, armed at
    // character-end and checked before starting the next element.
    @Volatile var acsValue: Int = 0

    private val ditMs  get() = (1200.0 / wpm).roundToInt()
    private val dahMs  get() = ditMs * 3
    private val gapMs  get() = ditMs

    // Physical paddle state — written by main thread, read by keyer thread
    @Volatile private var dit = false
    @Volatile private var dah = false

    // Edge detection state — main thread only
    @Volatile private var prevDit = false
    @Volatile private var prevDah = false

    // Memory latches — set by main thread on leading edge, cleared by keyer thread after element
    @Volatile private var ditMem = false
    @Volatile private var dahMem = false

    // Keyer-thread-only state
    private var state    = State.IDLE
    private var ditLast  = false
    private var deadline = 0L
    private var elementStart = 0L
    private var keyIsDown = false
    private var acsGateUntil = 0L

    // Ultimatic: track when paddle opened for debounce
    private val BOUNCE_MS = 5L
    @Volatile private var ditOpenedAt = 0L
    @Volatile private var dahOpenedAt = 0L

    // Straight key state (keyer-thread only)
    private var skPrevDown   = false
    private var skDownAt     = 0L
    private var skUpAt       = 0L
    private var skWaitingGap = false
    private var skWordGapSent = false

    // Word-gap detection (keyer-thread only): the character-boundary gap
    // above fires quickly (matches the real device's tight iambic timing),
    // but the DECODED TEXT should still only get a visible space between
    // WORDS, not between every letter — so track how long we have sat idle
    // since the last character boundary and fire a second, distinct "  "
    // (double-space) event once that idle time crosses a word-gap threshold.
    private var idleSince   = 0L
    private var wordGapSent = false

    var onSymbol: ((String) -> Unit)? = null

    // Expose physical state for MainActivity to read when building combined input
    val ditState: Boolean get() = dit
    val dahState: Boolean get() = dah

    private var thread: Thread? = null

    fun start() {
        // If already alive, nothing to do
        if (thread?.isAlive == true) return
        // Reset state so a fresh start is clean
        state     = State.IDLE
        ditMem    = false; dahMem    = false
        dit       = false; dah       = false
        keyIsDown = false
        idleSince = 0L; wordGapSent = false
        acsGateUntil = 0L
        skUpAt = 0L; skWaitingGap = false; skWordGapSent = false
        CwAudioNative.setPlaying(false)
        thread = Thread({
            while (!Thread.currentThread().isInterrupted) {
                try { tick(); Thread.sleep(1) }
                catch (e: InterruptedException) { Thread.currentThread().interrupt(); break }
            }
        }, "cw-keyer").also { it.isDaemon = true; it.start() }
    }

    fun stop() {
        thread?.interrupt()
        setKey(false)
        state = State.IDLE
    }

    fun setInputs(newDit: Boolean, newDah: Boolean) {
        val now = System.currentTimeMillis()

        if (mode == Mode.STRAIGHT) {
            dit = newDit   // keyer thread reads dit to drive straight key
            return
        }

        // Set memory on leading edge only
        if (newDit && !prevDit) ditMem = true
        if (newDah && !prevDah) dahMem = true

        // Ultimatic: when a new paddle comes in while other is held, suppress older
        if (mode == Mode.ULTIMATIC) {
            if (!newDit && prevDit) ditOpenedAt = now
            if (!newDah && prevDah) dahOpenedAt = now
            if (newDit && prevDit && newDah && !prevDah && now - ditOpenedAt > BOUNCE_MS) ditMem = false
            if (newDah && prevDah && newDit && !prevDit && now - dahOpenedAt > BOUNCE_MS) dahMem = false
        }

        dit    = newDit
        dah    = newDah
        prevDit = newDit
        prevDah = newDah
    }

    private fun tick() {
        val now = System.currentTimeMillis()

        if (mode == Mode.STRAIGHT) {
            tickStraight(now)
            return
        }

        // Snapshot volatile state once per tick
        val d = dit; val h = dah
        val dm = ditMem; val hm = dahMem

        when (state) {
            State.IDLE -> {
                if (d || h || dm || hm) {
                    // AutoChar Spc: hold off starting the next character's first
                    // element until the gate opens — the paddle press/memory
                    // stays pending (nothing is cleared here) so it fires the
                    // instant the gate clears, just like the real device's
                    // acsTimer check in its DIT/DAH keyer-state cases.
                    if (acsValue == 0 || now >= acsGateUntil) state = State.KEY_START
                } else if (!wordGapSent && idleSince != 0L && now - idleSince >= ditMs * 6) {
                    onSymbol?.invoke("  ")
                    wordGapSent = true
                }
            }

            State.KEY_START -> {
                val sendDit = decideDit(d, h, dm, hm)
                setKey(true)
                elementStart = now
                deadline = now + (if (sendDit) ditMs else dahMs)
                state = if (sendDit) State.DIT else State.DAH
                onSymbol?.invoke(if (sendDit) "·" else "—")
            }

            State.DIT -> {
                // Enhanced Curtis mode (Iambic B/Ultimatic): from curtisBDitTiming%
                // into this dit onward, poll the OPPOSITE (dah) paddle only —
                // mirrors m32_v6.ino's KEYED-state curtistimer check.
                if ((mode == Mode.IAMBIC_B || mode == Mode.ULTIMATIC) && !dahMem && h &&
                    now >= elementStart + 2 + (ditMs * curtisBDitTiming / 100)) {
                    dahMem = true
                }
                if (now >= deadline) {
                    setKey(false)
                    ditMem = false
                    ditLast = true
                    deadline = now + gapMs
                    state = State.INTER_ELEMENT
                }
            }

            State.DAH -> {
                if ((mode == Mode.IAMBIC_B || mode == Mode.ULTIMATIC) && !ditMem && d &&
                    now >= elementStart + 2 + (dahMs * curtisBDahTiming / 100)) {
                    ditMem = true
                }
                if (now >= deadline) {
                    setKey(false)
                    dahMem = false
                    ditLast = false
                    deadline = now + gapMs
                    state = State.INTER_ELEMENT
                }
            }

            State.INTER_ELEMENT -> {
                // Iambic B/Ultimatic: while both held during inter-element gap, queue opposite
                if ((mode == Mode.IAMBIC_B || mode == Mode.ULTIMATIC) && d && h) {
                    if (ditLast) dahMem = true else ditMem = true
                }
                if (now >= deadline) {
                    // Re-snapshot to catch any paddle changes during the gap
                    val d2 = dit; val h2 = dah; val dm2 = ditMem; val hm2 = dahMem
                    if (d2 || h2 || dm2 || hm2) state = State.KEY_START
                    else {
                        state = State.IDLE
                        onSymbol?.invoke(" ")
                        idleSince = now
                        wordGapSent = false
                        if (acsValue > 0) acsGateUntil = now + ditMs * (acsValue + 1)
                    }
                }
            }
        }
    }

    private fun tickStraight(now: Long) {
        val keyDown = dit
        when {
            keyDown && !skPrevDown -> {
                // Key down
                skDownAt     = now
                skWaitingGap = false
                setKey(true)
            }
            !keyDown && skPrevDown -> {
                // Key up — classify by duration
                setKey(false)
                val dur = now - skDownAt
                onSymbol?.invoke(if (dur < ditMs * 2) "·" else "—")
                skUpAt        = now
                skWaitingGap  = true
                skWordGapSent = false
            }
            !keyDown && skWaitingGap -> {
                // Silence after key-up — emit char separator after 3 dits
                if (now - skUpAt >= ditMs * 3) {
                    onSymbol?.invoke(" ")
                    skWaitingGap = false
                }
            }
            !keyDown && !skWaitingGap && !skWordGapSent && skUpAt != 0L -> {
                // Still idle well past the character gap — that's a word gap
                // (see the iambic path's idleSince/wordGapSent for why this is
                // a separate "  " event rather than another plain " ").
                if (now - skUpAt >= ditMs * 7) {
                    onSymbol?.invoke("  ")
                    skWordGapSent = true
                }
            }
        }
        skPrevDown = keyDown
    }

    private fun decideDit(d: Boolean, h: Boolean, dm: Boolean, hm: Boolean): Boolean {
        if (mode == Mode.NON_SQUEEZE) return if (ditLast) !(h || hm) else (d || dm)
        if (d && h) return !ditLast
        if (d || dm) return true
        return false
    }

    private fun setKey(on: Boolean) {
        if (on == keyIsDown) return
        keyIsDown = on
        tone.setPlaying(on)
    }
}
