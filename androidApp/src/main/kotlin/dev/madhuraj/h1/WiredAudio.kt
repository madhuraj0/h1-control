package dev.madhuraj.h1

import android.content.Context
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Detects the headphones connected over USB-C, where they are a USB audio device and switch Bluetooth off
 * (so the control channel is unavailable), and reports what audio formats the phone and headphones support.
 */
class WiredAudio(context: Context) {

    data class State(
        val connected: Boolean = false,
        /** Sample rates the headphones accept, ascending. Empty when the device doesn't say. */
        val sampleRates: List<Int> = emptyList(),
        /** Integer PCM bit depths the headphones accept, ascending. */
        val bitDepths: List<Int> = emptyList(),
        /** Whether the phone can send audio unaltered to them (Android 14+), null if unknown. */
        val bitPerfect: Boolean? = null,
    )

    private val audio = context.getSystemService(AudioManager::class.java)
    private val usb = context.getSystemService(UsbManager::class.java)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        audio.registerAudioDeviceCallback(
            object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = refresh()
                override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = refresh()
            },
            Handler(Looper.getMainLooper()),
        )
        refresh()
    }

    fun refresh() {
        val h1Attached = usb?.deviceList?.values?.any { it.vendorId == USB_VENDOR_ID && it.productId == USB_PRODUCT_ID } == true
        val output = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_USB_HEADSET || it.type == AudioDeviceInfo.TYPE_USB_DEVICE }
        if (!h1Attached || output == null) {
            _state.value = State()
            return
        }
        val bitPerfect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            audio.getSupportedMixerAttributes(output).any { it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT }
        } else {
            null
        }
        _state.value = State(
            connected = true,
            sampleRates = output.sampleRates.distinct().sorted(),
            bitDepths = output.encodings.toList().mapNotNull(::bitsOf).distinct().sorted(),
            bitPerfect = bitPerfect,
        )
    }

    private fun bitsOf(encoding: Int): Int? = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT -> 32
        else -> null
    }

    private companion object {
        /** JieLi USB IDs reported by the Studio H1 when plugged in. */
        const val USB_VENDOR_ID = 0x3654
        const val USB_PRODUCT_ID = 0x4A55
    }
}
