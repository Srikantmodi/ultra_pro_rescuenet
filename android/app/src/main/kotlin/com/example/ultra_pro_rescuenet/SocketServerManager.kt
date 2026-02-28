package com.example.ultra_pro_rescuenet

import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.*
import java.io.DataInputStream
import java.io.DataOutputStream
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

    /// FIX RELAY-2.3: Public health check — true only if the server loop is
    /// running AND the underlying socket is open. Used by WifiP2pHandler to
    /// detect a dead server after P2P group teardown and restart it.
    val isAlive: Boolean get() = isRunning && serverSocket?.isClosed == false

    fun start() {
        if (isRunning) {
            Log.w(TAG, "Server already running")
            return
        }

        scope.launch {
            try {
                // FIX RELAY-1.1: ALWAYS bind to 0.0.0.0 (all interfaces).
                //
                // The old code (FIX D-3) bound to the P2P group owner interface
                // (p2p-wlan0-*, 192.168.49.x). This caused the server to DIE after
                // the first connectAndSendPacket cycle because:
                //   1. Connect-and-send creates a P2P group → p2p-wlan0-x appears
                //   2. After send, removeGroup() tears down the P2P group
                //   3. The p2p-wlan0-x interface disappears
                //   4. ServerSocket bound to that interface can no longer accept()
                //   5. All subsequent relay attempts fail — Goal node is deaf
                //
                // Binding to 0.0.0.0 means the server accepts on ANY interface:
                // regular Wi-Fi, P2P (when active), loopback, etc. The P2P layer
                // already routes 192.168.49.x traffic to us when a group is formed,
                // regardless of which interface the ServerSocket is bound to.
                Log.d(TAG, "🔗 Binding to all interfaces (0.0.0.0)")
                serverSocket = ServerSocket(PORT)
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
