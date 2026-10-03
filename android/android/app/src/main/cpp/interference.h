// Interference simulation for the received ("other station") signal:
// band noise (with swell and crackle), QSB fading, pitch drift and QRM (a second keyed station). Pure DSP, no Android
// dependencies, so it can be compiled and tested on the host.
//
// Threading: setters are called from any thread (atomics); beginBlock() and
// process() only from the audio callback thread.
#pragma once

#include <atomic>
#include <cmath>
#include <cstdint>

// RBJ band-pass, constant 0 dB peak gain, double precision (float poles this
// close to the unit circle at a low centre frequency get noisy).
struct BandPass {
    double b0 = 0, a1 = 0, a2 = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    void set(double fc, double q, double sampleRate) {
        const double w0    = 2.0 * M_PI * fc / sampleRate;
        const double alpha = std::sin(w0) / (2.0 * q);
        const double a0    = 1.0 + alpha;
        b0 = alpha / a0;
        a1 = -2.0 * std::cos(w0) / a0;
        a2 = (1.0 - alpha) / a0;
    }
    double run(double x) {
        const double y = b0 * x - b0 * x2 - a1 * y1 - a2 * y2;   // b1 = 0, b2 = -b0
        x2 = x1; x1 = x;
        y2 = y1; y1 = y;
        return y;
    }
};

class Interference {
public:
    // All levels 0..1; 0 = off.
    void setParams(float noise, float qrm, float qsb, float drift, float filter, float color) {
        mColor.store(color, std::memory_order_relaxed);
        mFilter.store(filter, std::memory_order_relaxed);
        mNoise.store(noise, std::memory_order_relaxed);
        mQrm.store(qrm, std::memory_order_relaxed);
        mQsb.store(qsb, std::memory_order_relaxed);
        mDrift.store(drift, std::memory_order_relaxed);
    }

    // True while the generator plays the other station's signal. The user's
    // own keying (sidetone) never gets interference.
    void setRx(bool on) { mRx.store(on, std::memory_order_release); }

    // "Ambient": the screen keeps the band noise and QRM running between and
    // under the signals (also while the user keys). Only the other station's
    // tone gets QSB, filter and drift; the own sidetone stays clean.
    void setAmbient(bool on) { mAmbient.store(on, std::memory_order_release); }

    // Trainer signals (echo confirmation tone): the tone passes the limiter
    // untouched, only the noise bed is limited, so the tone is not distorted.
    void setClean(bool on) { mClean.store(on, std::memory_order_release); }

    // Once per audio block. `fc` = centre of the receiver filter (the sidetone
    // pitch), `vol` = tone volume (noise level is relative to it).
    void beginBlock(double sampleRate, double fc, float vol, int numFrames) {
        const float noise = mNoise.load(std::memory_order_relaxed);
        const float qsb   = mQsb.load(std::memory_order_relaxed);
        const float drift = mDrift.load(std::memory_order_relaxed);
        const float qrm   = mQrm.load(std::memory_order_relaxed);
        const bool  any   = noise > 0.0f || qsb > 0.0f || drift > 0.0f || qrm > 0.0f;
        const bool rx = mRx.load(std::memory_order_acquire);
        mTarget    = (any && rx) ? 1.0f : 0.0f;
        mBedTarget = ((noise > 0.0f || qrm > 0.0f) && (rx || mAmbient.load(std::memory_order_acquire))) ? 1.0f : 0.0f;
        mStep   = static_cast<float>(1.0 / (sampleRate * 0.05));   // 50 ms fade in/out
        if (mLevel <= 0.0f && mTarget <= 0.0f && mBedLevel <= 0.0f && mBedTarget <= 0.0f) { mActive = false; mDriftHz = 0.0; return; }
        mActive = true;

        // Receiver filter: 0 = wide (Q 1.0), 1 = very narrow CW filter (Q 28,
        // about 20 Hz wide at 600 Hz). Noise and crackle pass two identical
        // band-passes in series (12 dB/octave skirts: one stage still let
        // audible hiss through at 2-5 kHz); the tone passes one stage with
        // limited Q, otherwise every key-down/up rings ("klingelt").
        const float filter = mFilter.load(std::memory_order_relaxed);
        const double q     = 1.5 * std::pow(13.0, filter);   // Q 1.5..20
        mNoise1.set(fc, q, sampleRate);
        mNoise2.set(fc, q, sampleRate);
        mTone.set(fc, q < 3.0 ? q : 3.0, sampleRate);
        mQrmF.set(fc, q < 6.0 ? q : 6.0, sampleRate);   // QRM sits beside the tone: the filter may cut it
        mFc = fc; mSr = sampleRate;
        mQrmAmp = vol * qrm;
        // Audio colour of the receiver: fixed treble roll-off (two one-pole
        // low-passes), cut-off 800..3200 Hz.
        const float color = mColor.load(std::memory_order_relaxed);
        mLpA = 1.0 - std::exp(-2.0 * M_PI * (800.0 + 2400.0 * color) / sampleRate);

        // Noise level as SNR in a fixed 2.4 kHz reference bandwidth: +20 dB at
        // level -> 0 down to -10 dB at level 1. A narrower receiver filter
        // passes less of that noise, so it really improves the signal, as at
        // a real receiver. White noise power density is sigma^2 / (sr/2); the
        // chain's power gain (low-pass + both band-passes) is measured from
        // its impulse response.
        const double toneRms = vol * 0.7071;
        double noiseOutRms = 0.0;
        mNoiseGain = 0.0f;
        if (noise > 0.0f) {
            const double snrDb = 20.0 - 30.0 * noise;
            const double sigma = toneRms * std::pow(10.0, -snrDb / 20.0) *
                                 std::sqrt((sampleRate / 2.0) / 2400.0);
            if (mGKeyFc != fc || mGKeyQ != q || mGKeyLp != mLpA || mGKeySr != sampleRate) {
                mGKeyFc = fc; mGKeyQ = q; mGKeyLp = mLpA; mGKeySr = sampleRate;
                mChainPower = chainPower(fc, q, mLpA, sampleRate);
            }
            mNoiseGain = static_cast<float>(sigma / 0.577);   // uniform [-1,1) has RMS 0.577
            noiseOutRms = sigma * std::sqrt(mChainPower);
        }
        // Mild receiver AGC: keeps the sum from running into the limiter at
        // high noise levels without swallowing the tone.
        const double r = toneRms > 0.0 ? noiseOutRms / toneRms : 0.0;
        mOutGain = static_cast<float>(1.0 / std::sqrt(1.0 + 0.25 * r * r));
        const double dtb = numFrames / sampleRate;

        // Slowly wandering noise level (0.55..1.45, mean 1): real band noise
        // swells and ebbs instead of sitting at one constant level.
        mEnvTimer -= dtb;
        if (mEnvTimer <= 0.0) {
            mEnvTarget = 0.55f + 0.9f * (0.5f * (nextUniform() + 1.0f));
            mEnvTimer  = 0.1 + 0.3 * (0.5 * (nextUniform() + 1.0));
        }
        mEnv += (mEnvTarget - mEnv) * static_cast<float>(dtb / 0.12 < 1.0 ? dtb / 0.12 : 1.0);

        // Crackle (QRN): short random bursts that only bump the noise level
        // a little (real static sits within the hiss); rarer than the noise
        // level suggests, and smeared further by the receiver filter.
        mCrackleProb = static_cast<float>((0.3 + 3.0 * noise) / sampleRate);
        mCrackleDecay = static_cast<float>(std::exp(-1.0 / (0.002 * sampleRate)));

        // Pitch drift: mean-reverting random walk (time constant ~4 s), typical
        // excursion ~15 Hz and at most 30 Hz at level 1, like a slightly
        // unstable transmitter or receiver oscillator.
        mDriftHz += -mDriftHz * dtb / 4.0 + 18.4 * drift * nextUniform() * std::sqrt(dtb);
        const double lim = 30.0 * drift;
        if (mDriftHz >  lim) mDriftHz =  lim;
        if (mDriftHz < -lim) mDriftHz = -lim;

        // QSB: two slow sines with a wandering frequency, depth up to ~ -8 dB
        // (never fully silent).
        const double dt = numFrames / sampleRate;
        mLfoF += (nextUniform() * 0.02) * dt;                 // random walk, Hz
        if (mLfoF < 0.008) mLfoF = 0.008;
        if (mLfoF > 0.03) mLfoF = 0.03;
        mLfoP1 = std::fmod(mLfoP1 + 2.0 * M_PI * mLfoF * dt, 2.0 * M_PI);
        mLfoP2 = std::fmod(mLfoP2 + 2.0 * M_PI * mLfoF * 1.4 * dt, 2.0 * M_PI);
        const double m = 0.5 + 0.5 * (0.88 * std::sin(mLfoP1) + 0.12 * std::sin(mLfoP2));
        mQsbGain = static_cast<float>(1.0 - 0.6 * qsb * m);
    }

    // Offset to add to the tone frequency this block; fades with the rx level
    // so the pitch doesn't jump when the other station starts or stops.
    double freqOffsetHz() const { return mActive ? mDriftHz * mLevel : 0.0; }

    // One sample: `tone` is the clean (already enveloped) signal.
    float process(float tone) {
        if (!mActive) return tone;
        if (mLevel < mTarget)      mLevel = (mLevel + mStep < mTarget) ? mLevel + mStep : mTarget;
        else if (mLevel > mTarget) mLevel = (mLevel - mStep > mTarget) ? mLevel - mStep : mTarget;
        if (mBedLevel < mBedTarget)      mBedLevel = (mBedLevel + mStep < mBedTarget) ? mBedLevel + mStep : mBedTarget;
        else if (mBedLevel > mBedTarget) mBedLevel = (mBedLevel - mStep > mBedTarget) ? mBedLevel - mStep : mBedTarget;

        // Noise and crackle enter before the filter, like at a real receiver.
        const float white = nextUniform();
        double noiseIn = mBedLevel * mNoiseGain * mEnv * white;
        if (nextUniform() * 0.5f + 0.5f < mCrackleProb)
            mCrackle = 0.6f + 0.8f * (nextUniform() * 0.5f + 0.5f);   // extra amplitude vs. the noise
        mCrackle *= mCrackleDecay;
        noiseIn += mBedLevel * mNoiseGain * mEnv * mCrackle * nextUniform();

        // Fixed treble roll-off (two one-pole low-passes, 1.3 kHz): a receiver's
        // audio never has the full white hiss, even with a wide filter.
        mLp1 += mLpA * (noiseIn - mLp1);
        mLp2 += mLpA * (mLp1 - mLp2);
        noiseIn = mLp2;

        // Noise (and crackle) through both stages for steep skirts, the tone
        // through its own gentler stage.
        // The bed (noise, QRM) follows the ambient/rx level, the tone's own
        // processing (QSB, filter) only the rx level. With both equal this is
        // the plain "fade between the clean tone and the received signal".
        const float bed = mOutGain * mBedLevel * static_cast<float>(
            mNoise2.run(mNoise1.run(noiseIn)) + qrmSample());
        const float toneRx = static_cast<float>(mTone.run(tone * mQsbGain));
        if (mClean.load(std::memory_order_relaxed)) {
            const float y = tone + 0.3f * std::tanh(bed * (1.0f / 0.3f));
            return y > 1.0f ? 1.0f : (y < -1.0f ? -1.0f : y);
        }
        float out = tone * (1.0f - mLevel) + mLevel * mOutGain * toneRx + bed;
        return 0.95f * std::tanh(out * (1.0f / 0.95f));   // soft limiter, no hard clipping
    }

private:
    // Power gain of low-pass x2 + band-pass x2 for unit-variance white noise
    // (sum of the squared impulse response).
    static double chainPower(double fc, double q, double lpA, double sr) {
        BandPass b1, b2;
        b1.set(fc, q, sr); b2.set(fc, q, sr);
        double l1 = 0.0, l2 = 0.0, sum = 0.0;
        for (int n = 0; n < 8192; ++n) {
            l1 += lpA * ((n == 0 ? 1.0 : 0.0) - l1);
            l2 += lpA * (l1 - l2);
            const double y = b2.run(b1.run(l2));
            sum += y * y;
        }
        return sum;
    }

    float uni() { return 0.5f * (nextUniform() + 1.0f); }   // [0, 1)

    // QRM: another station, a second keyed oscillator beside the tone. It
    // sends random patterns in "overs" (3..12 characters at 12..28 wpm, on a
    // random frequency 100..350 Hz above or below), then pauses 1..4 s.
    void qrmNext() {
        const double dit = 1.2 / mQrmWpm * mSr;
        if (mQrmKey) {                                  // element over -> gap
            mQrmKey = false;
            if (--mQrmElems > 0)       mQrmRemain = static_cast<int>(dit);
            else if (--mQrmChars > 0) {
                mQrmElems  = 1 + static_cast<int>(uni() * 5.0f);
                mQrmRemain = static_cast<int>((uni() < 0.15f ? 7.0 : 3.0) * dit);
            } else {
                mQrmRemain  = static_cast<int>((1.0 + 3.0 * uni()) * mSr);
                mQrmNewOver = true;
            }
        } else {                                        // gap over -> element
            if (mQrmNewOver) {
                mQrmNewOver = false;
                mQrmWpm   = 12.0 + 16.0 * uni();
                mQrmChars = 3 + static_cast<int>(uni() * 10.0f);
                mQrmElems = 1 + static_cast<int>(uni() * 5.0f);
                const double off = 100.0 + 250.0 * uni();
                mQrmFreq = mFc + (uni() < 0.5f ? -off : off);
                if (mQrmFreq < 150.0) mQrmFreq = mFc + off;
            }
            mQrmKey = true;
            mQrmRemain = static_cast<int>((uni() < 0.4f ? 3.0 : 1.0) * 1.2 / mQrmWpm * mSr);
        }
    }

    double qrmSample() {
        if (mQrmAmp <= 0.0) return 0.0;
        if (--mQrmRemain <= 0) qrmNext();
        const double a = 1.0 - std::exp(-1.0 / (0.005 * mSr));   // 5 ms keying edges
        mQrmEnv += ((mQrmKey ? 1.0 : 0.0) - mQrmEnv) * a;
        mQrmPh += 2.0 * M_PI * mQrmFreq / mSr;
        if (mQrmPh > 2.0 * M_PI) mQrmPh -= 2.0 * M_PI;
        return mQrmF.run(mQrmAmp * mQrmEnv * std::sin(mQrmPh));
    }

    // xorshift32, uniform in [-1, 1).
    float nextUniform() {
        mSeed ^= mSeed << 13; mSeed ^= mSeed >> 17; mSeed ^= mSeed << 5;
        return static_cast<float>(mSeed) * (1.0f / 2147483648.0f) - 1.0f;
    }

    std::atomic<float> mNoise{0}, mQrm{0}, mQsb{0}, mDrift{0}, mFilter{0}, mColor{0.5f};
    std::atomic<bool>  mRx{false}, mAmbient{false}, mClean{false};

    // callback-thread state
    uint32_t mSeed = 0x9E3779B9u;
    bool   mActive = false;
    float  mBedLevel = 0.0f, mBedTarget = 0.0f;
    float  mLevel = 0.0f, mTarget = 0.0f, mStep = 0.0f;
    BandPass mNoise1, mNoise2, mTone, mQrmF;
    double mFc = 600.0, mSr = 48000.0, mQrmAmp = 0.0, mQrmEnv = 0.0, mQrmPh = 0.0, mQrmFreq = 800.0, mQrmWpm = 18.0;
    int    mQrmRemain = 0, mQrmElems = 0, mQrmChars = 0;
    bool   mQrmKey = false, mQrmNewOver = true;
    double mLpA = 0.1, mLp1 = 0.0, mLp2 = 0.0;
    double mGKeyFc = -1, mGKeyQ = -1, mGKeyLp = -1, mGKeySr = -1, mChainPower = 1.0;
    float  mOutGain = 1.0f, mNoiseGain = 0.0f, mQsbGain = 1.0f;
    float  mEnv = 1.0f, mEnvTarget = 1.0f;
    double mEnvTimer = 0.0;
    double mDriftHz = 0.0;
    float  mCrackleProb = 0.0f, mCrackleDecay = 0.99f, mCrackle = 0.0f;
    double mLfoF = 0.03, mLfoP1 = 0.0, mLfoP2 = 1.3;
};
