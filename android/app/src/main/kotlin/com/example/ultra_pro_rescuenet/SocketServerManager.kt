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

                // Read packet size (4 bytes, big-endian)
                val sizeBytes = ByteArray(4)
                inputStream.readFully(sizeBytes)
                val size = ByteBuffer.wrap(sizeBytes).int

                Log.d(TAG, "📦 Expecting packet size: $size bytes")

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
