// AAudio CW sidetone — low-latency sine wave with gain envelope.
// Runs entirely in the AAudio callback thread (no Java, no locking overhead).
// Called from CwAudioNative.kt via JNI.

#include <aaudio/AAudio.h>
#include <android/log.h>
#include <atomic>
#include <cmath>
#include <jni.h>

#define TAG "CwAudio"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static AAudioStream* gStream = nullptr;
static std::atomic<bool>   gPlaying{false};
static std::atomic<double> gFreqHz {600.0};
static std::atomic<float>  gVolume {0.7f};
// "Tone Softness" (M32 default 5 ms): attack/release time of the sidetone's
// gain envelope, in ms — same value for both edges, matching
// MorseOutput::setSidetoneEnvelope()'s symmetric ADSR (attack=release=t).
static std::atomic<float>  gEnvelopeMs {5.0f};

// These are only touched by the callback thread — no atomics needed.
static double gPhase = 0.0;
static double gGain  = 0.0;

static aaudio_data_callback_result_t audioCallback(
    AAudioStream* stream,
    void* /*userData*/,
    void* audioData,
    int32_t numFrames)
{
    float* out = static_cast<float*>(audioData);
    const double sampleRate = AAudioStream_getSampleRate(stream);
    const double step     = 2.0 * M_PI * gFreqHz.load(std::memory_order_relaxed) / sampleRate;
    const double envSec   = gEnvelopeMs.load(std::memory_order_relaxed) / 1000.0;
    const double rampUp   = 1.0 / (sampleRate * envSec);   // attack
    const double rampDown = rampUp;                        // release — same edge time, matches the real device
    const bool   playing  = gPlaying.load(std::memory_order_acquire);
    const float  vol      = gVolume.load(std::memory_order_relaxed);

    for (int i = 0; i < numFrames; ++i) {
        if (playing) {
            gGain = (gGain + rampUp  < 1.0) ? gGain + rampUp  : 1.0;
        } else {
            gGain = (gGain - rampDown > 0.0) ? gGain - rampDown : 0.0;
        }
        if (gGain > 0.0) {
            out[i] = static_cast<float>(std::sin(gPhase) * vol * gGain);
            gPhase += step;
            if (gPhase >= 2.0 * M_PI) gPhase -= 2.0 * M_PI;
        } else {
            out[i]  = 0.0f;
            gPhase  = 0.0;   // reset at zero crossing so next onset is clean
        }
    }
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

static void errorCallback(AAudioStream* /*stream*/, void* /*userData*/, aaudio_result_t error) {
    LOGE("AAudio error: %s", AAudio_convertResultToText(error));
    // Restart the stream on xrun
    if (gStream) {
        AAudioStream_requestStop(gStream);
        AAudioStream_requestStart(gStream);
    }
}

extern "C" {

JNIEXPORT jint JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_startStream(JNIEnv*, jclass)
{
    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t res = AAudio_createStreamBuilder(&builder);
    if (res != AAUDIO_OK) { LOGE("createStreamBuilder: %s", AAudio_convertResultToText(res)); return res; }

    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(builder, 1);
    // Try EXCLUSIVE first: direct hardware path = lowest possible latency
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_EXCLUSIVE);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setDataCallback(builder, audioCallback, nullptr);
    AAudioStreamBuilder_setErrorCallback(builder, errorCallback, nullptr);

    res = AAudioStreamBuilder_openStream(builder, &gStream);
    AAudioStreamBuilder_delete(builder);

    if (res != AAUDIO_OK) {
        LOGE("EXCLUSIVE failed (%s), retrying SHARED", AAudio_convertResultToText(res));
        AAudioStreamBuilder* b2 = nullptr;
        AAudio_createStreamBuilder(&b2);
        AAudioStreamBuilder_setFormat(b2, AAUDIO_FORMAT_PCM_FLOAT);
        AAudioStreamBuilder_setChannelCount(b2, 1);
        AAudioStreamBuilder_setPerformanceMode(b2, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
        AAudioStreamBuilder_setDataCallback(b2, audioCallback, nullptr);
        AAudioStreamBuilder_setErrorCallback(b2, errorCallback, nullptr);
        res = AAudioStreamBuilder_openStream(b2, &gStream);
        AAudioStreamBuilder_delete(b2);
        if (res != AAUDIO_OK) { LOGE("openStream shared: %s", AAudio_convertResultToText(res)); return res; }
    }

    res = AAudioStream_requestStart(gStream);
    if (res != AAUDIO_OK) LOGE("requestStart: %s", AAudio_convertResultToText(res));
    return res;
}

JNIEXPORT void JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_setPlaying(JNIEnv*, jclass, jboolean on)
{
    gPlaying.store(on, std::memory_order_release);
}

JNIEXPORT void JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_setFreqHz(JNIEnv*, jclass, jdouble hz)
{
    gFreqHz.store(hz, std::memory_order_relaxed);
}

JNIEXPORT void JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_setVolume(JNIEnv*, jclass, jfloat vol)
{
    gVolume.store(vol, std::memory_order_relaxed);
}

JNIEXPORT void JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_setEnvelopeMs(JNIEnv*, jclass, jfloat ms)
{
    gEnvelopeMs.store(ms, std::memory_order_relaxed);
}

JNIEXPORT void JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_stopStream(JNIEnv*, jclass)
{
    if (gStream) {
        AAudioStream_requestStop(gStream);
        AAudioStream_close(gStream);
        gStream = nullptr;
    }
}

JNIEXPORT jint JNICALL
Java_at_oe1wkl_morserino_1mobile_CwAudioNative_getLatencyMs(JNIEnv*, jclass)
{
    if (!gStream) return -1;
    int32_t burstFrames   = AAudioStream_getFramesPerBurst(gStream);
    int32_t sampleRate    = AAudioStream_getSampleRate(gStream);
    // Approximate output latency: 2 bursts (double-buffering) + output pipeline
    return (int)(2000.0 * burstFrames / sampleRate);
}

} // extern "C"
