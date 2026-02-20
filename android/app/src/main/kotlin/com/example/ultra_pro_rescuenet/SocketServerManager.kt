package com.example.ultra_pro_rescuenet

import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.*
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.zip.CRC32

class SocketServerManager(
    private val onPacketReceived: (String) -> Unit
) {
    companion object {
        private const val TAG = "SocketServer"
        private const val PORT = 8888
    }

    private var serverSocket: ServerSocket? = null
    private var isRunning = false
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun start() {
        if (isRunning) {
            Log.w(TAG, "Server already running")
            return
        }

        scope.launch {
            try {
                // FIX D-3: Bind to P2P group owner interface if active.
                // When this device is the GO (192.168.49.1), binding to 0.0.0.0
                // causes routing ambiguity on multi-interface devices (Wi-Fi + P2P).
                // Detect and bind specifically to the P2P interface.
                val bindAddress = detectP2pBindAddress()
                serverSocket = if (bindAddress != null) {
                    Log.d(TAG, "🔗 Binding to P2P interface: $bindAddress")
                    ServerSocket(PORT, 50, InetAddress.getByName(bindAddress))
                } else {
                    Log.d(TAG, "🔗 Binding to all interfaces (0.0.0.0)")
                    ServerSocket(PORT)
                }
                isRunning = true
                
                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅ SERVER STARTED ON PORT $PORT")
                Log.d(TAG, "═══════════════════════════════════")

                while (isRunning) {
                    try {
                        val clientSocket = serverSocket?.accept()
                        
                        if (clientSocket != null) {
                            Log.d(TAG, "📥 Client connected: ${clientSocket.inetAddress.hostAddress}")
                            handleClient(clientSocket)
                        }
                    } catch (e: Exception) {
                        if (isRunning) {
                            Log.e(TAG, "Error accepting client: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server error: ${e.message}", e)
            }
        }
    }

    private fun handleClient(socket: Socket) {
        scope.launch {
            try {
                val inputStream = DataInputStream(socket.getInputStream())
                val outputStream = DataOutputStream(socket.getOutputStream())

                // FIX D-8: Read packet header [4-byte size][4-byte CRC32]
                val headerBytes = ByteArray(8)
                inputStream.readFully(headerBytes)
                val headerBuf = ByteBuffer.wrap(headerBytes)
                val size = headerBuf.int
                val expectedCrc = headerBuf.int

                Log.d(TAG, "📦 Expecting packet size: $size bytes, CRC32: $expectedCrc")

                if (size <= 0 || size > 1048576) { // 1MB max
                    Log.e(TAG, "❌ Invalid packet size: $size")
                    outputStream.writeByte(0x15) // NAK
                    outputStream.flush()
                    socket.close()
                    return@launch
                }

                // Read actual data
                val dataBytes = ByteArray(size)
                inputStream.readFully(dataBytes)

                // FIX D-8: Validate CRC32 before ACKing.
                // Catches truncated/corrupted packets and avoids JSON parse exceptions.
                val crc = CRC32()
                crc.update(dataBytes)
                val actualCrc = crc.value.toInt()

                if (actualCrc != expectedCrc) {
                    Log.e(TAG, "❌ CRC32 mismatch! Expected=$expectedCrc, Actual=$actualCrc")
                    outputStream.writeByte(0x15) // NAK
                    outputStream.flush()
                    socket.close()
                    return@launch
                }

                val jsonData = String(dataBytes, Charsets.UTF_8)

                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅ PACKET RECEIVED")
                Log.d(TAG, "   Size: $size bytes")
                Log.d(TAG, "   Data: ${jsonData.take(200)}...")
                Log.d(TAG, "═══════════════════════════════════")

                // Send ACK
                outputStream.writeByte(0x06)
                outputStream.flush()

                // Close connection
                socket.close()

                // Notify Flutter
                // Notify Flutter
                withContext(Dispatchers.Main) {
                    onPacketReceived(jsonData)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error handling client: ${e.message}", e)
                try {
                    socket.close()
                } catch (closeEx: Exception) {
                    Log.e(TAG, "Error closing socket: ${closeEx.message}")
                }
            }
        }
    }

    /**
     * FIX D-3: Detect P2P Group Owner interface.
     * Scans network interfaces for the well-known p2p-wlan0-* interface.
     * If found and has the GO address (192.168.49.1), returns it.
     * Returns null if no P2P interface active (device is client or standalone).
     */
    private fun detectP2pBindAddress(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
            for (ni in interfaces) {
                // P2P group owner interface is typically named "p2p-wlan0-*" or "p2p0"
                if (ni.name.startsWith("p2p") || ni.name.contains("p2p")) {
                    for (addr in ni.inetAddresses) {
                        if (!addr.isLoopbackAddress && addr.hostAddress?.contains('.') == true) {
                            Log.d(TAG, "📡 Found P2P interface: ${ni.name} → ${addr.hostAddress}")
                            return addr.hostAddress
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not detect P2P interface: ${e.message}")
        }
        return null
    }

    fun stop() {
        Log.d(TAG, "Stopping server...")
        isRunning = false
        
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing server socket: ${e.message}")
        }
        
        serverSocket = null
        scope.cancel()
        
        Log.d(TAG, "✅ Server stopped")
    }
}
