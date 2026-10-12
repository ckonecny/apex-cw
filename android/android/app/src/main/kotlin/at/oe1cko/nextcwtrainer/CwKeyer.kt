package at.oe1cko.nextcwtrainer

import kotlin.math.roundToInt

/** What the keyer drives: the sidetone (CwTonePlugin), or a fake in tests. */
interface KeySink {
    fun setPlaying(on: Boolean)
}

/**
 * Port of doPaddleIambic() (m32_v6.ino, V9.0). Audited against the firmware
 * 2026-10-12, see docs/DECISIONS.md "Keyer audit". Paddle latches work like
 * the firmware's keyerControl bits: they are only written inside defined
 * windows (Curtis window during an element, the gap after the latency
 * window) and cleared when an element starts, so a press outside a window
 * is forgotten. Ultimatic uses its own memories, as in the firmware.
 *
 * All state is guarded by [lock]: setInputs() runs on the main thread, tick()
 * on the keyer thread, stop()/start() on whoever calls them.
 */
class CwKeyer(
    private val tone: KeySink,
    private val clock: () -> Long = System::currentTimeMillis,
) {

    private val lock = Any()

    enum class State { IDLE, START_DIT, START_DAH, KEYED_DIT, KEYED_DAH, INTER_ELEMENT }
    enum class Mode { IAMBIC_A, IAMBIC_B, ULTIMATIC, NON_SQUEEZE, STRAIGHT }

    @Volatile var wpm: Int = 20
    // Setting the mode restarts the straight-key speed measurement from the
    // straight-key start WPM (screens push the mode on entry, so each screen
    // starts fresh). The paddle WPM above plays no part for the straight key.
    @Volatile var mode: Mode = Mode.IAMBIC_A
        set(v) { field = v; straightDecoder.reset(straightStartWpm) }

    // Start speed estimate of the straight-key measurement (general setting).
    @Volatile var straightStartWpm: Int = 15
        set(v) { field = v; straightDecoder.reset(v) }

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

    // Word gap in dits, counted from the end of a character. Firmware keyer/
    // Trx modes use (InterWord Spc - 1) dits (m32_v6.ino, interWordTimer).
    @Volatile var wordGapDits: Int = 6

    // Straight key: echo word gap in dits (InterWord Spc + 1), 0 = none. Only
    // the Echo Trainer and Adventure set it, like the firmware's decoder in echo
    // mode (MorseDecoder.cpp INTERCHAR_ lacktime); otherwise the decoder uses
    // its measured-speed word gap. setInterWordSpace resets it to 0, so other
    // screens never inherit it.
    @Volatile var straightWordGapDits: Int = 0

    // Adaptive straight-key decoder (own measurement, never used by paddles).
    // It restarts from straightStartWpm whenever the keyer is (re)started.
    private val straightDecoder = StraightKeyDecoder()
    val measuredWpm: Int get() = straightDecoder.wpm

    // Display only: reports the measured straight-key WPM whenever it changes
    // (own channel, so the symbol stream stays untouched). null = nobody listens.
    var onMeasuredWpm: ((Int) -> Unit)? = null
    @Volatile private var reportedWpm = -1
    fun resendMeasuredWpm() { reportedWpm = -1 }

    private val ditMs  get() = (1200.0 / wpm).roundToInt()
    private val dahMs  get() = ditMs * 3
    private val gapMs  get() = ditMs

    // Physical paddle levels (main thread writes, keyer thread reads; lock)
    private var dit = false
    private var dah = false

    // A press seen by setInputs() is kept as a pulse until the next tick
    // samples it, so a very short touch is never missed between two ticks.
    // A pulse counts exactly like the firmware seeing the paddle down once.
    private var ditPulse = false
    private var dahPulse = false

    // Firmware keyerControl: DIT_L / DAH_L latches, DIT_LAST
    private var ditL = false
    private var dahL = false
    private var ditLast = false      // the element being/last sent is a dit
    private var ditFirst = false     // first element of this character was a dit

    // Ultimatic (firmware ultDitMemory/ultDahMemory/DIT_LAST_CLOSED)
    private var ultDitMem = false
    private var ultDahMem = false
    private var ditLastClosed = false
    private var prevDit = false
    private var prevDah = false
    private var ditOpenedAt = 0L
    private var dahOpenedAt = 0L

    // Keyer-thread state (under lock)
    private var state = State.IDLE
    private var deadline = 0L        // end of the current element / gap
    private var curtisAt = 0L        // from here on the opposite paddle is sampled
    private var latencyUntil = 0L    // end of the gap's "paddles insensitive" window
    private var keyIsDown = false
    private var acsGateUntil = 0L

    // Firmware default of the Latency preference (4/8 dit); the app has no setting for it.
    private val latencyEighths = 4

    // Contact-bounce guard for Ultimatic (CHATTER_GUARD_MS in the firmware)
    private val chatterGuardMs = 5L

    // Straight key state
    private var skPrevDown   = false

    // Word-gap detection: the character-boundary gap above fires quickly,
    // but the DECODED TEXT should only get a visible space between WORDS —
    // so track how long we have sat idle since the last character boundary
    // and fire a second, distinct "  " (double-space) event once that idle
    // time crosses the word-gap threshold.
    private var idleSince   = 0L
    private var wordGapSent = false

    var onSymbol: ((String) -> Unit)? = null

    // Expose physical state for MainActivity to read when building combined input
    val ditState: Boolean get() = synchronized(lock) { dit }
    val dahState: Boolean get() = synchronized(lock) { dah }

    // One flag per keyer thread: stop() cancels the running one and start()
    // may immediately begin a new one. (A bare thread.isAlive check lost the
    // restart when start() came right after stop(), see DECISIONS.md.)
    private class Worker { @Volatile var cancelled = false }
    private var worker: Worker? = null

    fun start() {
        synchronized(lock) {
            if (worker?.cancelled == false) return
            // Reset state so a fresh start is clean
            state     = State.IDLE
            ditL = false; dahL = false; ditPulse = false; dahPulse = false
            ultDitMem = false; ultDahMem = false
            ditLast = false; ditFirst = false
            dit = false; dah = false; prevDit = false; prevDah = false
            keyIsDown = false
            idleSince = 0L; wordGapSent = false
            acsGateUntil = 0L
            skPrevDown = false
            // Keeps the measured speed across stop/start (Echo Trainer restarts the
            // keyer per word); the mode setter is what restarts the measurement.
            straightDecoder.softReset()
            reportedWpm = -1
            tone.setPlaying(false)
            val w = Worker().also { worker = it }
            Thread({
                while (!w.cancelled && !Thread.currentThread().isInterrupted) {
                    try { tick(w); Thread.sleep(1) }
                    catch (e: InterruptedException) { break }
                }
            }, "cw-keyer").also { it.isDaemon = true; it.start() }
        }
    }

    fun stop() {
        synchronized(lock) {
            worker?.cancelled = true
            setKey(false)
            state = State.IDLE
        }
    }

    fun setInputs(newDit: Boolean, newDah: Boolean) {
        synchronized(lock) {
            if (mode == Mode.STRAIGHT) {
                dit = newDit   // keyer thread reads dit to drive straight key
                return
            }
            val now = clock()
            // Rising edges: pulse for the next sample, and the Ultimatic
            // memories (firmware doPaddleIambic, before the state switch).
            if (!newDit && prevDit) ditOpenedAt = now
            if (!newDah && prevDah) dahOpenedAt = now
            if (newDit && !prevDit) {
                ditPulse = true
                ditLastClosed = true
                val bounce = now - ditOpenedAt < chatterGuardMs
                if (!(bounce && ditLast)) ultDitMem = true
            }
            if (newDah && !prevDah) {
                dahPulse = true
                ditLastClosed = false
                val bounce = now - dahOpenedAt < chatterGuardMs
                if (!(bounce && !ditLast)) ultDahMem = true
            }
            dit = newDit; dah = newDah
            prevDit = newDit; prevDah = newDah
        }
    }

    private fun tick(w: Worker) {
        synchronized(lock) {
            if (w.cancelled) return
            tick()
        }
    }

    // One step of the state machine; the caller holds [lock] (tests call it
    // directly with a fake clock).
    internal fun tick() {
        val now = clock()

        if (mode == Mode.STRAIGHT) {
            tickStraight(now)
            return
        }

        // What the firmware sees as "the paddle is down" this round
        val sd = dit || ditPulse
        val sh = dah || dahPulse
        ditPulse = false; dahPulse = false

        when (state) {
            State.IDLE -> {
                if (sd || sh) {
                    ditL = ditL || sd; dahL = dahL || sh
                    ditFirst = sd                       // a squeeze starts with the dit
                    state = if (sd) State.START_DIT else State.START_DAH
                } else if (!wordGapSent && idleSince != 0L && now - idleSince >= ditMs * wordGapDits) {
                    onSymbol?.invoke("  ")
                    wordGapSent = true
                }
            }

            State.START_DIT -> {
                // AutoChar Spc: stay here until the gate opens (acsTimer check
                // in the firmware's DIT/DAH states); the latches stay pending.
                if (acsValue > 0 && now <= acsGateUntil) return
                ditL = false; dahL = false; ultDitMem = false
                ditLast = true
                startElement(now, ditMs, dit = true)
            }

            State.START_DAH -> {
                if (acsValue > 0 && now <= acsGateUntil) return
                ditL = false; dahL = false; ultDahMem = false
                ditLast = false
                startElement(now, dahMs, dit = false)
            }

            State.KEYED_DIT, State.KEYED_DAH -> {
                if (now >= deadline) {
                    setKey(false)
                    deadline = now + gapMs
                    latencyUntil = now + latencyEighths * ditMs / 8L
                    state = State.INTER_ELEMENT
                } else if (now >= curtisAt) {
                    // Curtis window: only the OPPOSITE paddle is sampled
                    if (ditLast) dahL = dahL || sh else ditL = ditL || sd
                }
            }

            State.INTER_ELEMENT -> {
                if (now < latencyUntil) {
                    // right after the element the paddle just used is insensitive
                    if (ditLast) dahL = dahL || sh else ditL = ditL || sd
                } else {
                    ditL = ditL || sd; dahL = dahL || sh
                    if (now >= deadline) nextElementOrEnd(now)
                }
            }
        }
    }

    private fun startElement(now: Long, lengthMs: Int, dit: Boolean) {
        curtisAt = when (mode) {
            Mode.IAMBIC_B ->
                now + 2 + lengthMs * (if (dit) curtisBDitTiming else curtisBDahTiming) / 100
            Mode.NON_SQUEEZE -> now + 3
            else -> Long.MAX_VALUE   // Iambic A: no early look; Ultimatic ignores it
        }
        setKey(true)
        deadline = now + lengthMs
        state = if (dit) State.KEYED_DIT else State.KEYED_DAH
        onSymbol?.invoke(if (dit) "·" else "—")
    }

    // End of the inter-element gap: firmware `switch (keyerControl)`.
    private fun nextElementOrEnd(now: Long) {
        if (mode == Mode.ULTIMATIC) ultimaticSelect()
        val sendDit: Boolean? = when {
            ditL && dahL -> when (mode) {
                Mode.NON_SQUEEZE -> ditFirst         // repeat the character's first element
                Mode.ULTIMATIC -> ditLastClosed
                else -> !ditLast                     // iambic: alternate
            }
            ditL -> true
            dahL -> false
            else -> null
        }
        if (sendDit != null) {
            state = if (sendDit) State.START_DIT else State.START_DAH
            return
        }
        // no latch: the character is complete
        state = State.IDLE
        onSymbol?.invoke(" ")
        idleSince = now
        wordGapSent = false
        if (acsValue > 0) acsGateUntil = now + ditMs * (acsValue + 1)
        ditL = false; dahL = false; ditLast = false
        ultDitMem = false; ultDahMem = false
    }

    // Firmware ultimaticSelect(): decide from the memories and the LIVE paddle
    // levels, and express the answer in the latch bits.
    private fun ultimaticSelect() {
        ditL = false; dahL = false
        when {
            ultDitMem && ultDahMem -> if (ditLastClosed) ditL = true else dahL = true
            ultDitMem -> ditL = true
            ultDahMem -> dahL = true
            dit && dah -> if (ditLastClosed) ditL = true else dahL = true
            dit -> ditL = true
            dah -> dahL = true
        }
    }

    private fun tickStraight(now: Long) {
        val keyDown = dit
        straightDecoder.echoWordGapDits = straightWordGapDits
        when {
            keyDown && !skPrevDown -> {
                setKey(true)
                straightDecoder.keyDown(now)
            }
            !keyDown && skPrevDown -> {
                setKey(false)
                straightDecoder.keyUp(now)?.let { onSymbol?.invoke(it) }
            }
            !keyDown -> straightDecoder.tick(now)?.let { onSymbol?.invoke(it) }
        }
        skPrevDown = keyDown
        val m = straightDecoder.wpm
        if (m != reportedWpm) { reportedWpm = m; onMeasuredWpm?.invoke(m) }
    }

    private fun setKey(on: Boolean) {
        if (on == keyIsDown) return
        keyIsDown = on
        tone.setPlaying(on)
    }
}
