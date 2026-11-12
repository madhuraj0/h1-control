package dev.madhuraj.h1

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import dev.madhuraj.h1.core.HeadsetSession
import dev.madhuraj.h1.core.HeadsetState
import dev.madhuraj.h1.core.NoiseMode
import dev.madhuraj.h1.core.RealmeFrame
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.UUID

/**
 * Owns the RFCOMM connection to the headphones and exposes their state. One instance per process
 * (see [H1App]), shared by the activity and the Quick Settings tiles.
 */
class HeadsetController(private val context: Context) {

    enum class Link { DISCONNECTED, CONNECTING, CONNECTED }

    data class UiState(
        val link: Link = Link.DISCONNECTED,
        val deviceAddress: String? = null,
        val deviceName: String? = null,
        val headset: HeadsetState = HeadsetState(),
        val error: String? = null,
        /**
         * Button-mode values (game mode, spatial audio, …) as last reported, kept across app restarts.
         * The headphones only report these when the button is pressed, so they can be out of date.
         */
        val lastSeenButtonFeatures: Map<Int, Int> = emptyMap(),
    ) {
        val gameMode: Boolean? get() = lastSeenButtonFeatures[RealmeFrame.FEATURE_GAME_MODE]?.let { it != 0 }
        val spatialAudio: Boolean? get() = lastSeenButtonFeatures[RealmeFrame.FEATURE_SPATIAL_AUDIO]?.let { it != 0 }
    }

    data class PairedDevice(val address: String, val name: String)

    private val prefs = context.getSharedPreferences("h1", Context.MODE_PRIVATE)
    private val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** All protocol work runs here, so [HeadsetSession] is only touched from one thread at a time. */
    @OptIn(ExperimentalCoroutinesApi::class)
    private val serial = Dispatchers.IO.limitedParallelism(1)
    private val connectLock = Mutex()

    private val _state = MutableStateFlow(
        UiState(deviceAddress = prefs.getString(KEY_ADDRESS, null), lastSeenButtonFeatures = loadButtonFeatures()),
    )
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var socket: BluetoothSocket? = null
    private var session: HeadsetSession? = null
    private var linkJob: Job? = null
    private var reconnectJob: Job? = null

    /** True while something (the app or a tile) wants a connection; false after an explicit disconnect. */
    @Volatile
    private var wantConnected = false

    init {
        // Reconnect as soon as the headphones' Bluetooth link comes back (e.g. after an LDAC switch, which
        // resets the audio connection and drops the control channel with it).
        ContextCompat.registerReceiver(
            context,
            object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    val device = IntentCompat.getParcelableExtra(intent, BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    if (device?.address != _state.value.deviceAddress) return
                    val connected = when (intent.action) {
                        BluetoothDevice.ACTION_ACL_CONNECTED -> true
                        BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED ->
                            intent.getIntExtra(BluetoothProfile.EXTRA_STATE, -1) == BluetoothProfile.STATE_CONNECTED
                        else -> false
                    }
                    if (connected && wantConnected && _state.value.link != Link.CONNECTED) scheduleReconnect()
                }
            },
            IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            },
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun pairedDevices(): List<PairedDevice> {
        if (!hasPermission()) return emptyList()
        return adapter?.bondedDevices.orEmpty()
            .map { PairedDevice(it.address, it.name ?: it.address) }
            .sortedWith(compareByDescending<PairedDevice> { looksLikeH1(it.name) }.thenBy { it.name.lowercase() })
    }

    /** Picks the headphones automatically the first time, if exactly one paired device looks like them. */
    fun autoSelect() {
        if (_state.value.deviceAddress != null) return
        pairedDevices().filter { looksLikeH1(it.name) }.singleOrNull()?.let { selectDevice(it.address) }
    }

    fun selectDevice(address: String) {
        prefs.edit().putString(KEY_ADDRESS, address).apply()
        disconnect()
        prefs.edit().remove(KEY_FEATURES).apply()
        _state.update { UiState(deviceAddress = address) }
        connect()
    }

    fun connect() {
        wantConnected = true
        scope.launch { ensureConnected() }
    }

    fun disconnect() {
        wantConnected = false
        reconnectJob?.cancel()
        closeSocket()
        _state.update { it.copy(link = Link.DISCONNECTED) }
    }

    fun refresh() = withSession { it.requestStatus() }

    /** Debug builds: sends one raw RCSP command (see MainActivity's "op"/"payload" extras). */
    fun sendRaw(opcode: Int, payload: ByteArray) = withSession {
        Log.i(TAG, "-> raw op=%02X payload=%s".format(opcode, payload.joinToString(" ") { "%02X".format(it) }))
        it.sendRaw(opcode, payload)
    }

    /** Debug builds: logs the full capability report and status (see MainActivity's "probe" extra). */
    fun probe() = withSession {
        it.requestTargetInfo()
        it.requestStatus()
    }

    fun setNoiseMode(mode: NoiseMode) = withSession { it.setNoiseMode(mode) }

    /** Off → Transparency → Noise cancelling → Off, the same order as the ANC button. */
    fun cycleNoiseMode() = withSession { session ->
        val next = when (session.state.noiseMode) {
            NoiseMode.OFF -> NoiseMode.TRANSPARENCY
            NoiseMode.TRANSPARENCY -> NoiseMode.ANC
            NoiseMode.ANC, null -> NoiseMode.OFF
        }
        session.setNoiseMode(next)
    }

    private fun withSession(block: (HeadsetSession) -> Unit) {
        wantConnected = true
        scope.launch {
            if (!ensureConnected()) return@launch
            withContext(serial) { session?.let(block) }
        }
    }

    @SuppressLint("MissingPermission")
    /** [retrying]: a background reconnect attempt; failures keep showing "Connecting…" instead of an error. */
    private suspend fun ensureConnected(retrying: Boolean = false): Boolean = connectLock.withLock {
        if (_state.value.link == Link.CONNECTED && socket?.isConnected == true) return true

        val address = _state.value.deviceAddress ?: return fail("Choose your headphones first.")
        if (!hasPermission()) return fail("Bluetooth permission is needed.")
        val adapter = adapter ?: return fail("This phone has no Bluetooth.")
        if (!adapter.isEnabled) return fail("Bluetooth is off.")

        _state.update { it.copy(link = Link.CONNECTING, error = null) }
        val device = adapter.getRemoteDevice(address)
        val newSocket = try {
            device.createRfcommSocketToServiceRecord(SPP_UUID).also { it.connect() }
        } catch (e: IOException) {
            Log.w(TAG, "connect failed: ${e.message}")
            if (retrying) return false
            return fail("Couldn't connect. Check the headphones are on and connected to this phone.")
        } catch (e: SecurityException) {
            return fail("Bluetooth permission is needed.")
        }

        val output = newSocket.outputStream
        val newSession = HeadsetSession { bytes ->
            try {
                output.write(bytes)
                output.flush()
            } catch (e: IOException) {
                Log.w(TAG, "write failed", e)
            }
        }
        newSession.onStateChanged = { headset ->
            _state.update { current ->
                val features = current.lastSeenButtonFeatures + headset.buttonFeatures
                if (features != current.lastSeenButtonFeatures) saveButtonFeatures(features)
                current.copy(headset = headset, lastSeenButtonFeatures = features)
            }
        }
        newSession.onMessage = { Log.d(TAG, "<- $it") }

        socket = newSocket
        session = newSession
        _state.update { it.copy(link = Link.CONNECTED, deviceName = device.name ?: address, error = null) }
        linkJob = scope.launch { runLink(newSocket, newSession) }
        withContext(serial) { newSession.requestStatus() }
        true
    }

    private suspend fun runLink(socket: BluetoothSocket, session: HeadsetSession) {
        val poller = scope.launch {
            while (isActive) {
                delay(BATTERY_POLL_MS)
                withContext(serial) { session.requestStatus() }
            }
        }
        val buffer = ByteArray(1024)
        try {
            val input = socket.inputStream
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                val chunk = buffer.copyOf(n)
                withContext(serial) { session.onBytes(chunk) }
            }
        } catch (e: IOException) {
            Log.i(TAG, "link closed: ${e.message}")
        } finally {
            poller.cancel()
            if (this.socket === socket) {
                closeSocket()
                _state.update { it.copy(link = Link.DISCONNECTED) }
                // Dropped without being asked to (headphones reset their link, went out of range, …).
                if (wantConnected) scheduleReconnect()
            }
        }
    }

    /** Retries with growing pauses for about two minutes, showing "Connecting…" meanwhile. */
    private fun scheduleReconnect() {
        if (reconnectJob?.isActive == true) return
        reconnectJob = scope.launch {
            _state.update { it.copy(link = Link.CONNECTING, error = null) }
            for ((attempt, pause) in RECONNECT_DELAYS_MS.withIndex()) {
                delay(pause)
                if (!wantConnected) return@launch
                if (ensureConnected(retrying = attempt < RECONNECT_DELAYS_MS.lastIndex)) return@launch
                _state.update { if (it.link != Link.CONNECTED) it.copy(link = Link.CONNECTING) else it }
            }
            fail("Lost connection to the headphones. Tap Connect to try again.")
        }
    }

    private fun closeSocket() {
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        socket = null
        session = null
    }

    private fun loadButtonFeatures(): Map<Int, Int> =
        prefs.getString(KEY_FEATURES, null).orEmpty().split(",").mapNotNull { entry ->
            val (k, v) = entry.split("=").takeIf { it.size == 2 } ?: return@mapNotNull null
            (k.toIntOrNull() ?: return@mapNotNull null) to (v.toIntOrNull() ?: return@mapNotNull null)
        }.toMap()

    private fun saveButtonFeatures(features: Map<Int, Int>) =
        prefs.edit().putString(KEY_FEATURES, features.entries.joinToString(",") { "${it.key}=${it.value}" }).apply()

    private fun fail(message: String): Boolean {
        _state.update { it.copy(link = Link.DISCONNECTED, error = message) }
        return false
    }

    private fun looksLikeH1(name: String) = name.contains("studio", ignoreCase = true) || name.contains("H1")

    private companion object {
        const val TAG = "H1"
        const val KEY_ADDRESS = "device_address"
        const val KEY_FEATURES = "button_features"
        const val BATTERY_POLL_MS = 60_000L
        val RECONNECT_DELAYS_MS = listOf(1_500L, 3_000L, 5_000L, 8_000L, 13_000L, 20_000L, 30_000L, 40_000L)

        /** Standard Serial Port Profile UUID; on the H1 it maps to RFCOMM channel 1 (JieLi RCSP). */
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
