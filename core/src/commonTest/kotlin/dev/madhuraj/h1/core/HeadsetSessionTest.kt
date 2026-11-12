package dev.madhuraj.h1.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** All byte strings below were captured from a real Studio H1 (firmware 2.4.0). */
class HeadsetSessionTest {
    private fun hex(s: String): ByteArray = s.split(" ").filter { it.isNotBlank() }.map { it.toInt(16).toByte() }.toByteArray()

    private val statusResponse = hex(
        "FE DC BA 00 07 00 58 00 02 FF 02 00 26 16 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 " +
            "02 06 00 02 09 00 08 0A 00 00 00 00 00 00 00 0A 0D 00 00 00 00 00 00 00 00 00 1D 0E 03 00 00 00 00 00 00 00 " +
            "00 00 01 40 00 00 00 40 00 00 00 02 40 00 00 00 40 00 00 00 02 0F 00 EF",
    )

    private val setAncAckAndPush = hex(
        "FE DC BA 00 08 00 02 00 02 EF FE DC BA 80 09 00 0D 01 FF 0A 0D 01 40 00 00 00 40 00 00 00 EF",
    )

    private fun session(sent: MutableList<ByteArray> = mutableListOf()) = HeadsetSession { sent += it }

    @Test
    fun encodesStatusRequestLikeTheProbe() {
        assertEquals("FE DC BA C0 07 00 06 01 FF FF FF FF FF EF", Commands.getStatus(1).toHex())
    }

    @Test
    fun encodesNoiseModeLikeTheVerifiedCommand() {
        assertEquals(
            "FE DC BA C0 08 00 0D 02 FF 0A 0D 01 40 00 00 00 40 00 00 00 EF",
            Commands.setNoiseMode(2, NoiseMode.ANC, Commands.DEFAULT_ACTIVE_GAINS).toHex(),
        )
        assertEquals(
            "FE DC BA C0 08 00 0D 06 FF 0A 0D 00 00 00 00 00 00 00 00 00 EF",
            Commands.setNoiseMode(6, NoiseMode.OFF, Commands.OFF_GAINS).toHex(),
        )
    }

    @Test
    fun parsesStatusResponse() {
        val s = session()
        s.onBytes(statusResponse)
        assertEquals(38, s.state.batteryPercent)
        assertEquals(NoiseMode.OFF, s.state.noiseMode)
        assertEquals(listOf(NoiseMode.OFF, NoiseMode.ANC, NoiseMode.TRANSPARENCY), s.state.supportedNoiseModes)
        assertNull(s.state.gameMode)
    }

    @Test
    fun appliesPushAfterSettingMode() {
        val s = session()
        s.onBytes(statusResponse)
        s.onBytes(setAncAckAndPush)
        assertEquals(NoiseMode.ANC, s.state.noiseMode)
    }

    @Test
    fun handlesFramesSplitAcrossReads() {
        val s = session()
        statusResponse.toList().chunked(5).forEach { s.onBytes(it.toByteArray()) }
        assertEquals(38, s.state.batteryPercent)
    }

    @Test
    fun setNoiseModeUsesGainsReportedByHeadphones() {
        val sent = mutableListOf<ByteArray>()
        val s = session(sent)
        s.onBytes(statusResponse)
        s.setNoiseMode(NoiseMode.TRANSPARENCY)
        assertEquals("FE DC BA C0 08 00 0D 01 FF 0A 0D 02 40 00 00 00 40 00 00 00 EF", sent.last().toHex())
        assertEquals(NoiseMode.TRANSPARENCY, s.state.noiseMode)
    }

    @Test
    fun tracksGameModeAndSpatialFromButtonEvents() {
        val s = session()
        s.onBytes(hex("85 86 87 02 04 01"))
        assertEquals(true, s.state.gameMode)
        s.onBytes(hex("85 86 87 02 04 00 85 86 87 02 05 06"))
        assertEquals(false, s.state.gameMode)
        assertEquals(true, s.state.spatialAudio)
        s.onBytes(hex("85 86 87 02 05 00"))
        assertEquals(false, s.state.spatialAudio)
    }

    @Test
    fun recordsUnidentifiedButtonFeatures() {
        val s = session()
        s.onBytes(hex("85 86 87 02 09 01 85 86 87 02 04 01"))
        assertEquals(mapOf(9 to 1, 4 to 1), s.state.buttonFeatures)
    }

    @Test
    fun skipsUnknownBytesAndRecovers() {
        val parser = FrameParser()
        val messages = parser.feed(hex("0C 07 55 55 AA BE 36 00 04 00 01 00 00 85 86 87 02 04 01"))
        assertIs<Incoming.Unknown>(messages[0])
        val event = assertIs<Incoming.RealmeEvent>(messages[1])
        assertEquals(4, event.feature)
        assertEquals(1, event.value)
    }

    @Test
    fun waitsForPartialHeader() {
        val parser = FrameParser()
        assertTrue(parser.feed(hex("FE DC")).isEmpty())
        val messages = parser.feed(hex("BA 00 08 00 02 00 02 EF"))
        val response = assertIs<Incoming.RcspResponse>(messages.single())
        assertEquals(Rcsp.Op.SET_SYS_INFO, response.opcode)
        assertEquals(0, response.status)
    }

    @Test
    fun answersCommandsThatWantAResponse() {
        val sent = mutableListOf<ByteArray>()
        val s = session(sent)
        s.onBytes(hex("FE DC BA C0 09 00 02 07 FF EF"))
        assertEquals("FE DC BA 00 09 00 02 00 07 EF", sent.single().toHex())
    }
}
