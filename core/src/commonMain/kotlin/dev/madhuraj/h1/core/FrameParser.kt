package dev.madhuraj.h1.core

/** A message decoded from the byte stream. */
sealed interface Incoming {
    /** The headphones answering one of our commands. */
    class RcspResponse(val opcode: Int, val status: Int, val sn: Int, val payload: ByteArray) : Incoming {
        override fun toString() = "RcspResponse(op=${opcode.hex2()} status=$status sn=$sn payload=${payload.toHex()})"
    }

    /** A command sent by the headphones (e.g. the sys-info push after a setting changes). */
    class RcspCommand(val opcode: Int, val needsResponse: Boolean, val sn: Int, val payload: ByteArray) : Incoming {
        override fun toString() = "RcspCommand(op=${opcode.hex2()} sn=$sn payload=${payload.toHex()})"
    }

    /** A realme `85 86 87` notification. */
    class RealmeEvent(val data: ByteArray) : Incoming {
        val feature: Int? get() = data.getOrNull(0)?.u()
        val value: Int? get() = data.getOrNull(1)?.u()
        override fun toString() = "RealmeEvent(${data.toHex()})"
    }

    /** Bytes that did not form a known frame. */
    class Unknown(val bytes: ByteArray) : Incoming {
        override fun toString() = "Unknown(${bytes.toHex()})"
    }
}

private fun Int.hex2() = toString(16).padStart(2, '0').uppercase()

/**
 * Splits the RFCOMM byte stream into messages. Frames may arrive split across reads or several to a read;
 * anything unrecognised is reported as [Incoming.Unknown] and skipped.
 */
class FrameParser(private val maxBodyLength: Int = 4096) {
    private var buffer = ByteArray(0)

    fun feed(data: ByteArray): List<Incoming> {
        buffer += data
        val out = mutableListOf<Incoming>()
        val skipped = mutableListOf<Byte>()
        fun flushSkipped() {
            if (skipped.isNotEmpty()) {
                out += Incoming.Unknown(skipped.toByteArray())
                skipped.clear()
            }
        }

        var pos = 0
        loop@ while (pos < buffer.size) {
            val remaining = buffer.size - pos
            when {
                startsWith(pos, Rcsp.HEADER) -> {
                    if (remaining < 7) break@loop
                    val len = (buffer[pos + 5].u() shl 8) or buffer[pos + 6].u()
                    if (len < 1 || len > maxBodyLength) {
                        skipped += buffer[pos++]
                        continue@loop
                    }
                    val total = 7 + len + 1
                    if (remaining < total) break@loop
                    if (buffer[pos + total - 1] != Rcsp.END) {
                        skipped += buffer[pos++]
                        continue@loop
                    }
                    flushSkipped()
                    val frame = buffer.copyOfRange(pos, pos + total)
                    out += decodeRcsp(frame) ?: Incoming.Unknown(frame)
                    pos += total
                }
                startsWith(pos, RealmeFrame.HEADER) -> {
                    if (remaining < 4) break@loop
                    val total = 4 + buffer[pos + 3].u()
                    if (remaining < total) break@loop
                    flushSkipped()
                    out += Incoming.RealmeEvent(buffer.copyOfRange(pos + 4, pos + total))
                    pos += total
                }
                isPartialHeader(pos) -> break@loop
                else -> skipped += buffer[pos++]
            }
        }
        flushSkipped()
        buffer = buffer.copyOfRange(pos, buffer.size)
        return out
    }

    private fun startsWith(pos: Int, header: ByteArray): Boolean {
        if (buffer.size - pos < header.size) return false
        return header.indices.all { buffer[pos + it] == header[it] }
    }

    /** True when the bytes left at [pos] could be the start of a header that hasn't fully arrived. */
    private fun isPartialHeader(pos: Int): Boolean {
        val remaining = buffer.size - pos
        return listOf(Rcsp.HEADER, RealmeFrame.HEADER).any { header ->
            remaining < header.size && (0 until remaining).all { buffer[pos + it] == header[it] }
        }
    }

    private fun decodeRcsp(frame: ByteArray): Incoming? {
        val flag = frame[3].u()
        val opcode = frame[4].u()
        val body = frame.copyOfRange(7, frame.size - 1)
        return if (flag and Rcsp.FLAG_COMMAND != 0) {
            if (body.isEmpty()) return null
            Incoming.RcspCommand(
                opcode = opcode,
                needsResponse = flag and Rcsp.FLAG_NEEDS_RESPONSE != 0,
                sn = body[0].u(),
                payload = body.copyOfRange(1, body.size),
            )
        } else {
            if (body.size < 2) return null
            Incoming.RcspResponse(opcode = opcode, status = body[0].u(), sn = body[1].u(), payload = body.copyOfRange(2, body.size))
        }
    }
}
