package dev.madhuraj.h1.tiles

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import dev.madhuraj.h1.HeadsetController
import dev.madhuraj.h1.HeadsetController.Link
import dev.madhuraj.h1.MainActivity
import dev.madhuraj.h1.core.NoiseMode
import dev.madhuraj.h1.headsetController
import dev.madhuraj.h1.label
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import dev.madhuraj.h1.H1App
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Shared behaviour: follow the controller's state while the tile is visible, connect on demand. */
abstract class HeadsetTile : TileService() {
    protected val controller: HeadsetController get() = headsetController
    private val wiredState get() = (applicationContext as H1App).wiredAudio.state
    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        scope = MainScope().also { scope ->
            scope.launch {
                combine(controller.state, wiredState) { state, wired -> state to wired.connected }.collect { (state, wired) ->
                    val tile = qsTile ?: return@collect
                    if (wired) {
                        // Bluetooth is off while the headphones are on USB-C; nothing to control.
                        tile.state = Tile.STATE_UNAVAILABLE
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = "Wired"
                    } else {
                        render(tile, state)
                    }
                    tile.updateTile()
                }
            }
        }
        if (controller.hasPermission()) controller.connect()
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val state = controller.state.value
        when {
            !controller.hasPermission() || state.deviceAddress == null -> openApp()
            state.link != Link.CONNECTED -> controller.connect()
            else -> onTileClick(state)
        }
    }

    protected abstract fun render(tile: Tile, state: HeadsetController.UiState)

    protected abstract fun onTileClick(state: HeadsetController.UiState)

    protected fun Tile.show(active: Boolean, subtitle: String) {
        state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) this.subtitle = subtitle
    }

    /** Subtitle for a tile while the headphones aren't connected, or null when they are. */
    protected fun HeadsetController.UiState.linkSubtitle(): String? = when (link) {
        Link.CONNECTED -> null
        Link.CONNECTING -> "Connecting…"
        Link.DISCONNECTED -> "Tap to connect"
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

/** Cycles Off → Transparency → Noise cancelling. */
class NoiseControlTile : HeadsetTile() {
    override fun render(tile: Tile, state: HeadsetController.UiState) {
        val mode = state.headset.noiseMode
        tile.show(
            active = state.link == Link.CONNECTED && mode != null && mode != NoiseMode.OFF,
            subtitle = state.linkSubtitle() ?: mode?.label ?: "Connected",
        )
    }

    override fun onTileClick(state: HeadsetController.UiState) = controller.cycleNoiseMode()
}

/** Toggles one mode on (or back to Off). */
abstract class NoiseModeTile(private val mode: NoiseMode) : HeadsetTile() {
    override fun render(tile: Tile, state: HeadsetController.UiState) {
        val on = state.link == Link.CONNECTED && state.headset.noiseMode == mode
        tile.show(active = on, subtitle = state.linkSubtitle() ?: if (on) "On" else "Off")
    }

    override fun onTileClick(state: HeadsetController.UiState) =
        controller.setNoiseMode(if (state.headset.noiseMode == mode) NoiseMode.OFF else mode)
}

class AncTile : NoiseModeTile(NoiseMode.ANC)

class TransparencyTile : NoiseModeTile(NoiseMode.TRANSPARENCY)
