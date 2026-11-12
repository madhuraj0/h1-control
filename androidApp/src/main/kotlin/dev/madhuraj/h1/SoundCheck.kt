package dev.madhuraj.h1

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin

/**
 * Generated test signals, played through whatever audio output is active. Signals are rendered on a
 * background thread and cached, so starting one never blocks the UI.
 */
class SoundCheck {

    enum class Test(val title: String, val description: String, val seconds: Double) {
        CHANNELS(
            "Left / right",
            "A tone in the left ear, then the right, then both. Checks the channels aren't swapped.",
            6.0,
        ),
        PAN(
            "Moving sound",
            "A chord that circles from ear to ear. Play it with spatial audio on, then off; the difference is the spatial effect.",
            10.0,
        ),
        HIGH_FREQUENCY(
            "High-frequency sweep",
            "A quiet sweep from 12 to 22 kHz. AAC and SBC usually cut off around 16–17 kHz; LDAC carries more. " +
                "Many adults can't hear above ~16 kHz, so silence near the end is normal. Keep the volume low.",
            12.0,
        ),
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val cache = ConcurrentHashMap<Test, ShortArray>()

    @Volatile
    private var track: AudioTrack? = null

    @Volatile
    private var requested: Test? = null

    init {
        // Render everything up front so the first tap plays immediately.
        worker.execute { Test.entries.forEach(::samples) }
    }

    fun play(test: Test) {
        stop()
        requested = test
        worker.execute {
            val data = samples(test)
            if (requested != test) return@execute // stopped or replaced while rendering
            val newTrack = buildTrack(data.size)
            newTrack.write(data, 0, data.size)
            newTrack.play()
            track = newTrack
        }
    }

    fun stop() {
        requested = null
        worker.execute {
            track?.let {
                runCatching { it.stop() }
                it.release()
            }
            track = null
        }
    }

    private fun samples(test: Test): ShortArray = cache.getOrPut(test) {
        when (test) {
            Test.CHANNELS -> channels()
            Test.PAN -> pan(test.seconds)
            Test.HIGH_FREQUENCY -> sweep(test.seconds)
        }
    }

    private fun buildTrack(sampleCount: Int): AudioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setSampleRate(RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .build(),
        )
        .setTransferMode(AudioTrack.MODE_STATIC)
        .setBufferSizeInBytes(sampleCount * 2)
        .build()

    /** Interleaved stereo frames: (left, right) per sample index. */
    private fun render(seconds: Double, frame: (t: Double) -> Pair<Double, Double>): ShortArray {
        val frames = (seconds * RATE).toInt()
        val out = ShortArray(frames * 2)
        for (i in 0 until frames) {
            val t = i.toDouble() / RATE
            // 20 ms fade in/out to avoid clicks.
            val fade = min(1.0, min(t, seconds - t) / 0.02)
            val (l, r) = frame(t)
            out[2 * i] = (l * fade * Short.MAX_VALUE).toInt().toShort()
            out[2 * i + 1] = (r * fade * Short.MAX_VALUE).toInt().toShort()
        }
        return out
    }

    private fun channels() = render(6.0) { t ->
        val tone = 0.3 * sin(2 * PI * 440 * t)
        when {
            t < 1.6 -> tone to 0.0
            t < 2.0 -> 0.0 to 0.0
            t < 3.6 -> 0.0 to tone
            t < 4.0 -> 0.0 to 0.0
            else -> tone to tone
        }
    }

    private fun pan(seconds: Double) = render(seconds) { t ->
        val chord = 0.12 * (sin(2 * PI * 261.6 * t) + sin(2 * PI * 329.6 * t) + sin(2 * PI * 392.0 * t))
        // Pulse so movement is easier to follow.
        val pulse = 0.6 + 0.4 * sin(2 * PI * 3 * t)
        val angle = (1 - cos(2 * PI * t / 5)) / 2 * (PI / 2) // left → right → left every 5 s, equal-power
        (chord * pulse * cos(angle)) to (chord * pulse * sin(angle))
    }

    private fun sweep(seconds: Double): ShortArray {
        val f0 = 12_000.0
        val f1 = 22_000.0
        val k = ln(f1 / f0)
        return render(seconds) { t ->
            // Exponential sweep; phase is the integral of the instantaneous frequency.
            val phase = 2 * PI * f0 * seconds / k * (exp(t / seconds * k) - 1)
            val s = 0.12 * sin(phase)
            s to s
        }
    }

    private companion object {
        const val RATE = 48_000
    }
}
