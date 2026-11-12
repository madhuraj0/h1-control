package dev.madhuraj.h1

import android.app.Application
import android.content.Context
import dev.madhuraj.h1.core.NoiseMode

class H1App : Application() {
    val controller by lazy { HeadsetController(this) }
    val codecMonitor by lazy { CodecMonitor(this) }
    val wiredAudio by lazy { WiredAudio(this) }
}

val Context.headsetController: HeadsetController
    get() = (applicationContext as H1App).controller

val NoiseMode.label: String
    get() = when (this) {
        NoiseMode.OFF -> "Off"
        NoiseMode.TRANSPARENCY -> "Transparency"
        NoiseMode.ANC -> "Noise cancelling"
    }
