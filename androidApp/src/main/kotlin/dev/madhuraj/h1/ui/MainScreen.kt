package dev.madhuraj.h1.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import dev.madhuraj.h1.CodecMonitor
import dev.madhuraj.h1.HeadsetController.Link
import dev.madhuraj.h1.HeadsetController.PairedDevice
import dev.madhuraj.h1.HeadsetController.UiState
import dev.madhuraj.h1.R
import dev.madhuraj.h1.SoundCheck
import dev.madhuraj.h1.WiredAudio
import dev.madhuraj.h1.core.NoiseMode
import dev.madhuraj.h1.label
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    state: UiState,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    pairedDevices: () -> List<PairedDevice>,
    onSelectDevice: (String) -> Unit,
    onConnect: () -> Unit,
    onNoiseMode: (NoiseMode) -> Unit,
    codec: CodecMonitor.State,
    wired: WiredAudio.State,
    soundCheck: SoundCheck,
) {
    var showPicker by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("H1 Control") },
                actions = {
                    if (hasPermission) {
                        IconButton(onClick = { showPicker = true }) {
                            Icon(painterResource(R.drawable.ic_headset), contentDescription = "Choose headphones")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            when {
                !hasPermission -> MessageCard(
                    title = "Bluetooth access",
                    body = "H1 Control needs permission to talk to your paired headphones.",
                    action = "Allow",
                    onAction = onRequestPermission,
                )
                state.deviceAddress == null -> MessageCard(
                    title = "Choose your headphones",
                    body = "Pair the Studio H1 in Bluetooth settings first, then pick it here.",
                    action = "Choose",
                    onAction = { showPicker = true },
                )
                wired.connected -> {
                    // Over USB-C the headphones switch Bluetooth off, so only audio info is available.
                    StatusCard(state, onConnect, wired = true)
                    WiredAudioSection(wired)
                    SoundCheckSection(soundCheck)
                    ButtonGuide()
                }
                else -> {
                    StatusCard(state, onConnect)
                    NoiseControl(state, onNoiseMode)
                    HeadphoneModes(state, codec)
                    AudioQuality(codec)
                    SoundCheckSection(soundCheck)
                    ButtonGuide()
                }
            }
        }
    }

    if (showPicker) {
        DevicePicker(
            devices = remember { pairedDevices() },
            selected = state.deviceAddress,
            onSelect = {
                showPicker = false
                onSelectDevice(it)
            },
            onDismiss = { showPicker = false },
        )
    }
}

@Composable
private fun StatusCard(state: UiState, onConnect: () -> Unit, wired: Boolean = false) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
    ) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painterResource(R.drawable.ic_headset),
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Column(
                modifier = Modifier
                    .padding(start = 16.dp)
                    .weight(1f),
            ) {
                Text(
                    state.deviceName ?: "Studio H1",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                val battery = state.headset.batteryPercent
                val status = when {
                    wired -> "Wired (USB-C)"
                    state.link == Link.CONNECTED -> if (battery != null) "Connected · $battery% battery" else "Connected"
                    state.link == Link.CONNECTING -> "Connecting…"
                    else -> "Not connected"
                }
                Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                state.error?.takeIf { !wired }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
            if (state.link == Link.DISCONNECTED && !wired) {
                FilledTonalButton(onClick = onConnect) { Text("Connect") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NoiseControl(state: UiState, onNoiseMode: (NoiseMode) -> Unit) {
    Section("Noise control") {
        val modes = listOf(NoiseMode.OFF, NoiseMode.TRANSPARENCY, NoiseMode.ANC)
        val enabled = state.link == Link.CONNECTED
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            modes.forEachIndexed { index, mode ->
                SegmentedButton(
                    selected = state.headset.noiseMode == mode,
                    onClick = { onNoiseMode(mode) },
                    shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                    enabled = enabled,
                    icon = {},
                ) {
                    Text(if (mode == NoiseMode.ANC) "ANC" else mode.label, maxLines = 1)
                }
            }
        }
        Note("Changes made with the ANC button aren't reported by the headphones, so this shows the last mode set from the phone.")
    }
}

@Composable
private fun HeadphoneModes(state: UiState, codec: CodecMonitor.State) {
    Section("Modes") {
        Card(modifier = Modifier.fillMaxWidth()) {
            ModeRow("Game mode", "Hold the ANC button for 1 s · only works with LDAC off", onOff(state.gameMode))
            ModeRow("Spatial audio", "Press the ANC button twice", onOff(state.spatialAudio))
            ModeRow("LDAC", "Press the ANC button 3 times", onOff(codec.current?.isLdac))
            ModeRow("Adaptive noise", "Hold ANC and + together for 1 s", "Not reported")
        }
        Note(
            "Switch these on the headphones. Game mode and spatial audio show the last state the headphones reported; " +
                "they only report it when you press the button. LDAC is read from the phone. Adaptive noise isn't reported at all.",
        )
    }
}

@Composable
private fun AudioQuality(codec: CodecMonitor.State) {
    Section("Audio quality") {
        Card(modifier = Modifier.fillMaxWidth()) {
            val current = codec.current
            ModeRow(
                "Codec in use",
                current?.let { listOfNotNull(formatFormat(it), it.ldacMode).joinToString(" · ") } ?: "Unknown",
                current?.name ?: "—",
            )
            val best = codec.best
            ModeRow(
                "Best this phone + H1 support",
                best?.let { "Up to ${formatFormat(it)}" } ?: "Unknown",
                best?.name ?: "—",
            )
        }
        codec.note?.let { Note(it) }
        Note(
            "Bluetooth audio is always compressed; even LDAC at 990 kbps is lossy, so \"lossless\" files can't reach the " +
                "headphones bit-for-bit. LDAC's best mode is the most this pair can carry. Choose it under Developer " +
                "options › Bluetooth audio LDAC codec: playback quality.",
        )
    }
}

@Composable
private fun WiredAudioSection(wired: WiredAudio.State) {
    Section("Wired audio") {
        Card(modifier = Modifier.fillMaxWidth()) {
            val rate = wired.sampleRates.maxOrNull()?.let { if (it % 1000 == 0) "${it / 1000} kHz" else "%.1f kHz".format(it / 1000.0) }
            val bits = wired.bitDepths.maxOrNull()?.let { "$it-bit" }
            val rates = wired.sampleRates.joinToString(", ") { r -> "%.4g".format(r / 1000.0) }
            ModeRow(
                "Headphones accept",
                if (rates.isEmpty()) "Formats not reported" else "$rates kHz",
                listOfNotNull(rate, bits).joinToString(" / ").ifEmpty { "—" },
            )
            ModeRow(
                "Bit-perfect playback",
                "Audio sent unaltered, in music players that support Android's USB bit-perfect mode",
                when (wired.bitPerfect) {
                    true -> "Supported"
                    false -> "Not supported"
                    null -> "Android 14+"
                },
            )
        }
        Note(
            "USB-C audio is uncompressed, unlike Bluetooth. Most apps' audio is still mixed by Android (usually at " +
                "48 kHz) before it reaches the headphones; only players using bit-perfect mode send files at their " +
                "original quality. While wired, the headphones turn Bluetooth off, so noise control and modes " +
                "can only be changed with their buttons.",
        )
    }
}

private fun formatFormat(codec: CodecMonitor.Codec): String {
    val rate = codec.sampleRates.maxOrNull()?.let { if (it % 1000 == 0) "${it / 1000} kHz" else "%.1f kHz".format(it / 1000.0) }
    val bits = codec.bitDepths.maxOrNull()?.let { "$it-bit" }
    return listOfNotNull(rate, bits).joinToString(" / ")
}

@Composable
private fun SoundCheckSection(soundCheck: SoundCheck) {
    var playing by remember { mutableStateOf<SoundCheck.Test?>(null) }
    LaunchedEffect(playing) {
        val test = playing ?: return@LaunchedEffect
        delay((test.seconds * 1000).toLong())
        playing = null
    }

    Section("Sound check") {
        Card(modifier = Modifier.fillMaxWidth()) {
            SoundCheck.Test.entries.forEachIndexed { index, test ->
                if (index > 0) HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                ListItem(
                    headlineContent = { Text(test.title) },
                    supportingContent = { Text(test.description) },
                    trailingContent = {
                        FilledTonalIconButton(onClick = {
                            if (playing == test) {
                                soundCheck.stop()
                                playing = null
                            } else {
                                soundCheck.play(test)
                                playing = test
                            }
                        }) {
                            Icon(
                                painterResource(if (playing == test) R.drawable.ic_pause else R.drawable.ic_play),
                                contentDescription = if (playing == test) "Stop" else "Play",
                            )
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = CardDefaults.cardColors().containerColor),
                )
            }
        }
    }
}

private val buttonGuide = listOf(
    "ANC button" to listOf(
        "Press" to "Transparency / ANC on / ANC off",
        "Press twice" to "Spatial audio on/off",
        "Press 3 times" to "LDAC on/off",
        "Hold 1 s" to "Game mode / music mode (LDAC must be off)",
    ),
    "O button" to listOf(
        "Press" to "Play/pause, answer or end a call",
        "Press twice" to "Voice assistant",
        "Press 3 times" to "Pairing mode",
        "Hold 1 s" to "Decline a call",
    ),
    "+ and − buttons" to listOf(
        "Press" to "Volume up / down",
        "Hold 2 s" to "Next / previous track",
    ),
    "ANC and + together" to listOf(
        "Hold 1 s" to "Adaptive noise on/off",
    ),
)

@Composable
private fun ButtonGuide() {
    var expanded by remember { mutableStateOf(false) }
    Section("Button guide") {
        Card(modifier = Modifier.fillMaxWidth()) {
            ListItem(
                headlineContent = { Text(if (expanded) "Hide button guide" else "Show what each button does") },
                modifier = Modifier.clickable { expanded = !expanded },
                colors = ListItemDefaults.colors(containerColor = CardDefaults.cardColors().containerColor),
            )
            if (expanded) {
                buttonGuide.forEachIndexed { index, (button, actions) ->
                    if (index > 0) HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                        Text(button, style = MaterialTheme.typography.titleSmall)
                        actions.forEach { (press, action) ->
                            Row(modifier = Modifier.padding(top = 4.dp)) {
                                Text(
                                    press,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.width(110.dp),
                                )
                                Text(action, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun onOff(value: Boolean?) = when (value) {
    true -> "On"
    false -> "Off"
    null -> "—"
}

@Composable
private fun ModeRow(title: String, supporting: String, value: String) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(supporting) },
        trailingContent = { Text(value, style = MaterialTheme.typography.labelLarge) },
        colors = ListItemDefaults.colors(containerColor = CardDefaults.cardColors().containerColor),
    )
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        content()
    }
}

@Composable
private fun MessageCard(title: String, body: String, action: String, onAction: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(body, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(12.dp))
            FilledTonalButton(onClick = onAction) { Text(action) }
        }
    }
}

@Composable
private fun DevicePicker(
    devices: List<PairedDevice>,
    selected: String?,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Choose headphones") },
        text = {
            if (devices.isEmpty()) {
                Text("No paired devices. Pair the headphones in Bluetooth settings first.")
            } else {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    devices.forEach { device ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelect(device.address) }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = device.address == selected, onClick = { onSelect(device.address) })
                            Column {
                                Text(device.name)
                                Text(device.address, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}
