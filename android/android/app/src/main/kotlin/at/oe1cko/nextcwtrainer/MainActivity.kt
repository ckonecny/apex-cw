package at.oe1cko.nextcwtrainer

import android.content.Context
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Set from Dart ("setKeepScreenOn") only while an actual training screen
    // (Keyer/Generator/Koch/Echo) is open — not on Home or Settings.
    private fun setKeepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private lateinit var tonePlugin:  CwTonePlugin
    private lateinit var keyer:       CwKeyer
    private lateinit var generator:   CwGenerator
    private lateinit var audioRouteManager: AudioRouteManager

    // Paddle configuration — loaded from SharedPreferences
    private var ditChar = 0xFC  // 'ü' (self-built vband default)
    private var dahChar = 0x2B  // '+'  (self-built vband default)

    // Learn mode: 0=off, 1=waiting for dit, 2=waiting for dah
    private var learnStep = 0
    private var settingsEventSink: EventChannel.EventSink? = null
    // Hören-Block, nach dem Aufdecken: Paddle wählt Wiederholen (Dit) / Weiter (Dah).
    // Dart schaltet das ein; der Tastendruck geht dann als Event nach Dart, nicht in den Keyer.
    @Volatile private var paddleChoiceActive = false
    private var genEventSink: EventChannel.EventSink? = null
    @Volatile private var keyDiagMode = false

    companion object {
        private const val SYMBOL_CHANNEL   = "at.oe1cko.nextcwtrainer/cw_symbols"
        private const val KEYER_CHANNEL    = "at.oe1cko.nextcwtrainer/cw_keyer"
        private const val GEN_CHANNEL      = "at.oe1cko.nextcwtrainer/cw_generator"
        private const val GEN_EV_CHANNEL   = "at.oe1cko.nextcwtrainer/cw_gen_events"
        private const val SETTINGS_CHANNEL = "at.oe1cko.nextcwtrainer/settings"
        private const val SETTINGS_EV      = "at.oe1cko.nextcwtrainer/settings_events"
        private const val PREFS_NAME       = "next_cw_trainer_prefs"
        private const val PREF_DIT         = "paddle_dit"
        private const val PREF_DAH         = "paddle_dah"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        loadPaddlePrefs()

        // ── Audio & Keyer ──────────────────────────────────────────────────────
        tonePlugin = CwTonePlugin(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CwTonePlugin.CHANNEL)
        )
        keyer     = CwKeyer(tonePlugin)
        generator = CwGenerator(tonePlugin)

        // Reopens the sidetone stream on whichever output device matches the
        // user's preference whenever USB/Bluetooth audio hardware is (un)plugged.
        audioRouteManager = AudioRouteManager(this) { activeLabel ->
            runOnUiThread { settingsEventSink?.success(mapOf("type" to "audioRoute", "value" to activeLabel)) }
        }
        audioRouteManager.start()

        // ── Keyer symbol stream → Dart ─────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SYMBOL_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    keyer.onSymbol = { sym -> runOnUiThread { events.success(sym) } }
                }
                override fun onCancel(args: Any?) { keyer.onSymbol = null }
            })

        // ── Generator events → Dart ────────────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, GEN_EV_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    genEventSink = events
                    generator.onChar    = { ch -> runOnUiThread { events.success(mapOf("type" to "char",    "value" to ch)) } }
                    generator.onWord    = { w  -> runOnUiThread { events.success(mapOf("type" to "word",    "value" to w))  } }
                    generator.onDone    = { maxWords -> runOnUiThread { events.success(mapOf("type" to "done", "value" to (if (maxWords) "maxWords" else ""))) } }
                    generator.onWaiting = {      runOnUiThread { events.success(mapOf("type" to "waiting", "value" to ""))  } }
                }
                override fun onCancel(args: Any?) {
                    genEventSink = null
                    generator.onChar = null; generator.onWord = null; generator.onDone = null; generator.onWaiting = null
                }
            })

        // ── Settings events → Dart (learn mode feedback) ──────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_EV)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) {
                    settingsEventSink = events
                }
                override fun onCancel(args: Any?) { settingsEventSink = null }
            })

        // ── Keyer config + touch paddles ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEYER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWpm"    -> { keyer.wpm  = (call.arguments as? Number)?.toInt() ?: 20; result.success(null) }
                    "setMode"   -> {
                        keyer.mode = uiIndexToKeyerMode((call.arguments as? Number)?.toInt() ?: 0)
                        result.success(null)
                    }
                    "setCurtisBTiming" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        keyer.curtisBDitTiming = (args?.get("dit") as? Number)?.toInt() ?: 75
                        keyer.curtisBDahTiming = (args?.get("dah") as? Number)?.toInt() ?: 45
                        result.success(null)
                    }
                    "setInterWordSpace" -> {
                        keyer.wordGapDits = ((call.arguments as? Number)?.toInt() ?: 7).coerceAtLeast(2) - 1
                        result.success(null)
                    }
                    "setAcs" -> {
                        keyer.acsValue = (call.arguments as? Number)?.toInt() ?: 0
                        result.success(null)
                    }
                    "setInputs" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        keyer.setInputs(args?.get("dit") as? Boolean ?: false,
                                        args?.get("dah") as? Boolean ?: false)
                        result.success(null)
                    }
                    "start"     -> { keyer.start(); result.success(null) }
                    "stop"      -> { keyer.stop();  result.success(null) }
                    else        -> result.notImplemented()
                }
            }

        // ── Generator control ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        keyer.stop()
                        @Suppress("UNCHECKED_CAST")
                        val args  = call.arguments as? Map<String, Any>
                        generator.wpm            = (args?.get("wpm")            as? Number)?.toInt() ?: 20
                        generator.kochLevel      = (args?.get("kochLevel")      as? Number)?.toInt() ?: 5
                        generator.mode           = CwGenerator.Mode.entries
                            .getOrElse((args?.get("mode") as? Number)?.toInt() ?: 0) { CwGenerator.Mode.RANDOM_CHARS }
                        generator.interCharSpace = (args?.get("interCharSpace") as? Number)?.toInt() ?: 3
                        generator.interWordSpace = (args?.get("interWordSpace") as? Number)?.toInt() ?: 7
                        generator.eachWordTwice  = args?.get("eachWordTwice")  as? Boolean ?: false
                        generator.groupLength    = (args?.get("groupLength")    as? Number)?.toInt() ?: 5
                        generator.randomOption   = (args?.get("randomOption")   as? Number)?.toInt() ?: 0
                        generator.wordLengthMax  = (args?.get("wordLengthMax")  as? Number)?.toInt() ?: 0
                        generator.stopAfterItem  = args?.get("stopAfterItem") as? Boolean ?: false
                        generator.abbrevLengthMax = (args?.get("abbrevLengthMax") as? Number)?.toInt() ?: 0
                        generator.maxWords        = (args?.get("maxWords")        as? Number)?.toInt() ?: 0
                        generator.callLengthOpt   = (args?.get("callLengthOpt")   as? Number)?.toInt() ?: 0
                        generator.callRegionOpt   = (args?.get("callRegionOpt")   as? Number)?.toInt() ?: 0
                        generator.callCommonOnly  = args?.get("callCommonOnly")  as? Boolean ?: false
                        generator.kochActive      = args?.get("kochActive")      as? Boolean ?: false
                        generator.start()
                        result.success(null)
                    }
                    "stop"    -> { generator.stop(); keyer.start(); result.success(null) }
                    "playOne" -> {
                        generator.playOne(call.arguments as? String ?: "")
                        result.success(null)
                    }
                    "playPatterns" -> {
                        @Suppress("UNCHECKED_CAST")
                        generator.playPatterns((call.arguments as? List<String>) ?: emptyList())
                        result.success(null)
                    }
                    "setWpm"  -> { generator.wpm = (call.arguments as? Number)?.toInt() ?: 20; result.success(null) }
                    "setInterCharSpace" -> {
                        generator.interCharSpace = (call.arguments as? Number)?.toInt() ?: 3
                        result.success(null)
                    }
                    "setInterWordSpace" -> {
                        generator.interWordSpace = (call.arguments as? Number)?.toInt() ?: 7
                        result.success(null)
                    }
                    "setPaddleChoice" -> {
                        paddleChoiceActive = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    "setKochChars" -> {
                        @Suppress("UNCHECKED_CAST")
                        val chars = call.arguments as? List<String>
                        if (!chars.isNullOrEmpty()) generator.kochChars = chars
                        result.success(null)
                    }
                    "setPracticeChars" -> {
                        @Suppress("UNCHECKED_CAST")
                        generator.practiceChars = (call.arguments as? List<String>) ?: emptyList()
                        result.success(null)
                    }
                    "setBoostLevel" -> {
                        generator.boostLevel = (call.arguments as? Number)?.toInt() ?: 0
                        result.success(null)
                    }
                    "getNextContent" -> {
                        // Not running: safe to reuse the shared generator instance just for
                        // content generation (e.g. from Echo Trainer for Words/Calls/Mixed).
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        generator.mode = CwGenerator.Mode.entries
                            .getOrElse((args?.get("mode") as? Number)?.toInt() ?: 0) { CwGenerator.Mode.RANDOM_CHARS }
                        generator.kochLevel     = (args?.get("kochLevel")     as? Number)?.toInt() ?: 5
                        generator.wordLengthMax = (args?.get("wordLengthMax") as? Number)?.toInt() ?: 0
                        generator.groupLength   = (args?.get("groupLength")   as? Number)?.toInt() ?: 5
                        generator.randomOption  = (args?.get("randomOption")  as? Number)?.toInt() ?: 0
                        generator.abbrevLengthMax = (args?.get("abbrevLengthMax") as? Number)?.toInt() ?: 0
                        generator.callLengthOpt   = (args?.get("callLengthOpt")   as? Number)?.toInt() ?: 0
                        generator.callRegionOpt   = (args?.get("callRegionOpt")   as? Number)?.toInt() ?: 0
                        generator.callCommonOnly  = args?.get("callCommonOnly")  as? Boolean ?: false
                        generator.kochActive      = args?.get("kochActive")      as? Boolean ?: false
                        result.success(generator.nextContent())
                    }
                    else      -> result.notImplemented()
                }
            }

        // ── Settings ──────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPaddleChars" -> result.success(mapOf(
                        "dit" to charDescription(ditChar),
                        "dah" to charDescription(dahChar)
                    ))
                    "startLearnPaddle" -> {
                        learnStep = 1
                        sendLearnEvent("step", "1")  // "Press Dit paddle"
                        result.success(null)
                    }
                    "cancelLearnPaddle" -> {
                        learnStep = 0
                        result.success(null)
                    }
                    "setKeyerMode" -> {
                        keyer.mode = uiIndexToKeyerMode((call.arguments as? Number)?.toInt() ?: 0)
                        result.success(null)
                    }
                    "setCurtisBTiming" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        keyer.curtisBDitTiming = (args?.get("dit") as? Number)?.toInt() ?: 75
                        keyer.curtisBDahTiming = (args?.get("dah") as? Number)?.toInt() ?: 45
                        result.success(null)
                    }
                    "setAcs" -> {
                        keyer.acsValue = (call.arguments as? Number)?.toInt() ?: 0
                        result.success(null)
                    }
                    "startKeyDiag" -> { keyDiagMode = true;  result.success(null) }
                    "stopKeyDiag"  -> { keyDiagMode = false; result.success(null) }
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "getOutputDeviceKinds" -> result.success(mapOf(
                        "preferred" to audioRouteManager.getPreferredKind(),
                        "available" to audioRouteManager.listAvailableKinds()
                    ))
                    "setOutputDeviceKind" -> {
                        audioRouteManager.setPreferredKind(
                            (call.arguments as? Number)?.toInt() ?: AudioRouteManager.KIND_AUTO)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        keyer.start()
    }

    // ── Key event interception ────────────────────────────────────────────────

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val chMeta = event.getUnicodeChar(event.metaState)
        val chRaw  = event.getUnicodeChar(0)

        // Key diagnostics: forward all down-events with full detail to Dart
        if (keyDiagMode && event.action == KeyEvent.ACTION_DOWN) {
            val desc = "keyCode=${event.keyCode} scanCode=${event.scanCode} " +
                "charMeta=0x${chMeta.toString(16)} charRaw=0x${chRaw.toString(16)} " +
                "meta=0x${event.metaState.toString(16)} " +
                "label=${KeyEvent.keyCodeToString(event.keyCode)}"
            sendLearnEvent("keyDiag", desc)
            // still fall through so paddles work during diag
        }

        // Learn mode: capture next two distinct key-down events
        // Accept any key that produces any code (raw or with meta)
        val anyChar = if (chMeta > 0) chMeta else chRaw
        if (learnStep > 0 && event.action == KeyEvent.ACTION_DOWN) {
            // Use keyCode as the identity if no unicode char available
            val id = if (anyChar > 0) anyChar else -(event.keyCode)
            return handleLearnKeyEvent(id)
        }

        val isDit = chMeta == ditChar || chRaw == ditChar || (ditChar < 0 && -event.keyCode == ditChar)
        val isDah = chMeta == dahChar || chRaw == dahChar || (dahChar < 0 && -event.keyCode == dahChar)
        if (isDit || isDah) {
            val down = event.action == KeyEvent.ACTION_DOWN
            // Generator paused after a word (Stop<Next>Rep): dit=repeat, dah=next — matches
            // the real device's paddle-driven autoStop, not the keyer.
            if (down && generator.awaitingChoice) {
                generator.choosePaddle(isDit)
                return true
            }
            if (paddleChoiceActive) {
                if (down && event.repeatCount == 0) {
                    runOnUiThread {
                        genEventSink?.success(mapOf("type" to "paddle", "value" to (if (isDit) "dit" else "dah")))
                    }
                }
                return true
            }
            keyer.setInputs(
                if (isDit) down else keyer.ditState,
                if (isDah) down else keyer.dahState
            )
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun handleLearnKeyEvent(ch: Int): Boolean {
        return when (learnStep) {
            1 -> {
                ditChar = ch
                learnStep = 2
                sendLearnEvent("step", "2")  // "Press Dah paddle"
                true
            }
            2 -> {
                if (ch == ditChar) return true  // same key pressed twice — wait for different key
                dahChar = ch
                learnStep = 0
                savePaddlePrefs()
                sendLearnEvent("done", "${charDescription(ditChar)} / ${charDescription(dahChar)}")
                true
            }
            else -> false
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private fun loadPaddlePrefs() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        ditChar = prefs.getInt(PREF_DIT, 0xFC)
        dahChar = prefs.getInt(PREF_DAH, 0x2B)
    }

    private fun savePaddlePrefs() {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(PREF_DIT, ditChar)
            .putInt(PREF_DAH, dahChar)
            .apply()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // UI order matches the real M32 "Keyer Mode" preference exactly:
    // Iambic A / Iambic B / Ultimatic / Non-Squeeze / Straight Key.
    private fun uiIndexToKeyerMode(idx: Int): CwKeyer.Mode = when (idx) {
        0 -> CwKeyer.Mode.IAMBIC_A
        1 -> CwKeyer.Mode.IAMBIC_B
        2 -> CwKeyer.Mode.ULTIMATIC
        3 -> CwKeyer.Mode.NON_SQUEEZE
        4 -> CwKeyer.Mode.STRAIGHT
        else -> CwKeyer.Mode.IAMBIC_A
    }

    private fun charDescription(code: Int): String {
        if (code < 0) return "keyCode=${-code} (${KeyEvent.keyCodeToString(-code)})"
        val ch = code.toChar()
        return when {
            ch.isLetterOrDigit() || ch in "[]{}()+-=_.,:;?!@#\$%^&*/<>" -> "'$ch' (U+${code.toString(16).uppercase().padStart(4,'0')})"
            code == 0xFC -> "'ü' (U+00FC)"
            else         -> "U+${code.toString(16).uppercase().padStart(4,'0')}"
        }
    }

    private fun sendLearnEvent(type: String, value: String) {
        runOnUiThread { settingsEventSink?.success(mapOf("type" to type, "value" to value)) }
    }

    override fun onDestroy() {
        keyer.stop()
        generator.stop()
        audioRouteManager.stop()
        CwAudioNative.stopStream()
        super.onDestroy()
    }
}
