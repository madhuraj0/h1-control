package dev.madhuraj.h1.core

/**
 * JieLi RCSP framing, as spoken by the Studio H1 on its serial-port (SPP) RFCOMM channel.
 *
 * ```
 * FE DC BA <flag> <opcode> <len hi> <len lo> <body…> EF
 * ```
 * - `flag` bit 7: the frame is a command (otherwise a response); bit 6: the sender wants a response.
 * - command body: `<sn> <payload…>`
 * - response body: `<status> <sn> <payload…>`
 * - `len` is the body length (big-endian).
 */
object Rcsp {
    val HEADER = byteArrayOf(0xFE.toByte(), 0xDC.toByte(), 0xBA.toByte())
    const val END: Byte = 0xEF.toByte()

    const val FLAG_COMMAND = 0x80
    const val FLAG_NEEDS_RESPONSE = 0x40

    /** Opcodes used by this app. */
    object Op {
        const val TARGET_INFO = 0x03
        const val GET_SYS_INFO = 0x07
        const val SET_SYS_INFO = 0x08
        /** Pushed by the headphones after a setting changes. */
        const val SYS_INFO_PUSH = 0x09
    }

    /** Function group "public" of the sys-info commands. */
    const val FUNCTION_PUBLIC = 0xFF

    /** Attributes of the public function group. */
    object Attr {
        const val BATTERY = 0x00
        const val CURRENT_NOISE_MODE = 0x0D
        const val ALL_NOISE_MODES = 0x0E
    }

    const val STATUS_OK = 0

    fun encodeCommand(opcode: Int, sn: Int, payload: ByteArray, needsResponse: Boolean = true): ByteArray {
        val flag = FLAG_COMMAND or (if (needsResponse) FLAG_NEEDS_RESPONSE else 0)
        val body = byteArrayOf(sn.toByte()) + payload
        return frame(flag, opcode, body)
    }

    fun encodeResponse(opcode: Int, status: Int, sn: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        val body = byteArrayOf(status.toByte(), sn.toByte()) + payload
        return frame(0, opcode, body)
    }

    private fun frame(flag: Int, opcode: Int, body: ByteArray): ByteArray =
        HEADER +
            byteArrayOf(flag.toByte(), opcode.toByte(), (body.size shr 8).toByte(), body.size.toByte()) +
            body +
            byteArrayOf(END)
}

/**
 * Short notification frames the headphones send when a button changes a realme-specific feature:
 * `85 86 87 <len> <feature> <value>`. One-way only; writing them back has no effect.
 */
object RealmeFrame {
    val HEADER = byteArrayOf(0x85.toByte(), 0x86.toByte(), 0x87.toByte())

    const val FEATURE_GAME_MODE = 0x04
    const val FEATURE_SPATIAL_AUDIO = 0x05
}

fun ByteArray.toHex(): String = joinToString(" ") { (it.toInt() and 0xFF).toString(16).padStart(2, '0').uppercase() }

internal fun Byte.u(): Int = toInt() and 0xFF
