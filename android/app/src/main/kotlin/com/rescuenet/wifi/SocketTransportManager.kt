package com.rescuenet.wifi

import android.util.Log
import kotlinx.coroutines.*
import java.io.*
import java.net.*
import java.nio.charset.StandardCharsets

/**
 * Manages TCP socket communication for mesh network data transfer.
 *
 * This is the "Muscle" of the Data Plane - handles the actual packet
 * transmission between nodes using the "Hit-and-Run" Store-and-Forward protocol:
 *
 * 1. Connect to target node
 * 2. Send JSON packet
 * 3. Wait for ACK
 * 4. Immediately disconnect (save battery)
 *
 * **Critical Implementation Notes:**
 *
 * 1. All connections have a STRICT 5000ms timeout to prevent battery drain.
 * 2. Socket operations run in background threads via coroutines.
 * 3. Server listens on port 8888 when in Relay/Goal mode.
 * 4. Each connection is short-lived (connect → send → ack → close).
 */
class SocketTransportManager {
    
    companion object {
        private const val TAG = "SocketTransportManager"
        
        // Connection port for mesh communication
        const val MESH_PORT = 8888
        
        // STRICT 5-second timeout (battery saver requirement)
        const val CONNECTION_TIMEOUT_MS = 5000
        const val READ_TIMEOUT_MS = 5000
        
        // Maximum packet size (1MB)
        const val MAX_PACKET_SIZE = 1024 * 1024
        
        // ACK message
        const val ACK_MESSAGE = "ACK"
        
        // End of message marker
        const val END_MARKER = "\n<END>\n"
    }

    private var serverSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Callback for received packets
    private var onPacketReceived: ((String, String) -> Unit)? = null
    private var onServerError: ((Exception) -> Unit)? = null

    /**
     * Starts the server socket to receive incoming packets.
     *
     * The server runs continuously, accepting connections and processing
     * packets from other mesh nodes.
     *
     * @param onPacketReceived Called when a complete packet is received (senderIp, packetJson)
     * @param onError Called when server encounters an error
     */
    fun startServer(
        onPacketReceived: (String, String) -> Unit,
        onError: (Exception) -> Unit
    ) {
        if (serverSocket != null) {
            Log.d(TAG, "Server already running")
            return
        }
        
        this.onPacketReceived = onPacketReceived
        this.onServerError = onError
        
        serverJob = scope.launch {
            try {
                serverSocket = ServerSocket(MESH_PORT).apply {
                    reuseAddress = true
                    soTimeout = 0 // No timeout for accept(), we'll handle it per-connection
                }
                
                Log.d(TAG, "Server started on port $MESH_PORT")
                
                while (isActive && serverSocket != null) {
                    try {
                        val clientSocket = serverSocket?.accept() ?: break
                        
                        // Handle each client in a separate coroutine
                        launch {
                            handleClientConnection(clientSocket)
                        }
                    } catch (e: SocketTimeoutException) {
                        // No client connected, continue waiting
                    } catch (e: SocketException) {
                        if (isActive) {
                            Log.e(TAG, "Socket exception while accepting: ${e.message}")
                        }
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server error: ${e.message}")
                withContext(Dispatchers.Main) {
                    onError(e)
                }
            }
        }
    }

    /**
     * Handles a single client connection.
     *
     * Protocol:
     * 1. Read until END_MARKER
     * 2. Parse packet
     * 3. Send ACK
     * 4. Close connection
     */
    private suspend fun handleClientConnection(clientSocket: Socket) {
        val senderIp = clientSocket.inetAddress.hostAddress ?: "unknown"
        Log.d(TAG, "Client connected from $senderIp")
        
        try {
            clientSocket.soTimeout = READ_TIMEOUT_MS
            
            val inputStream = BufferedReader(
                InputStreamReader(clientSocket.getInputStream(), StandardCharsets.UTF_8)
            )
            val outputStream = BufferedWriter(
                OutputStreamWriter(clientSocket.getOutputStream(), StandardCharsets.UTF_8)
            )
            
            // Read packet data until END_MARKER
            val packet = readPacket(inputStream)
            
            if (packet != null) {
                Log.d(TAG, "Received packet (${packet.length} bytes) from $senderIp")
                
                // Send ACK
                outputStream.write(ACK_MESSAGE)
                outputStream.flush()
                Log.d(TAG, "Sent ACK to $senderIp")
                
                // Notify callback on main thread
                withContext(Dispatchers.Main) {
                    onPacketReceived?.invoke(senderIp, packet)
                }
            } else {
                Log.w(TAG, "Received empty or invalid packet from $senderIp")
            }
        } catch (e: SocketTimeoutException) {
            Log.w(TAG, "Timeout reading from $senderIp")
        } catch (e: IOException) {
            Log.e(TAG, "IO error with client $senderIp: ${e.message}")
        } finally {
            try {
                clientSocket.close()
            } catch (e: IOException) {
                // Ignore close errors
            }
            Log.d(TAG, "Connection closed with $senderIp")
        }
    }

    /**
     * Reads a packet from the input stream until END_MARKER is found.
     */
    private fun readPacket(reader: BufferedReader): String? {
        val buffer = StringBuilder()
        var bytesRead = 0
        
        while (bytesRead < MAX_PACKET_SIZE) {
            val line = reader.readLine() ?: break
            
            if (line == "<END>") {
                // Found end marker, return packet
                return buffer.toString().trim()
            }
            
            buffer.append(line)
            buffer.append("\n")
            bytesRead += line.length + 1
        }
        
        // No end marker found
        return if (buffer.isNotEmpty()) buffer.toString().trim() else null
    }

    /**
     * Stops the server socket.
     */
    fun stopServer() {
        Log.d(TAG, "Stopping server")
        
        serverJob?.cancel()
        serverJob = null
        
        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.w(TAG, "Error closing server socket: ${e.message}")
        }
        serverSocket = null
    }

    /**
     * Sends a packet to a remote node.
     *
     * This is the client-side operation:
     * 1. Connect to target IP:8888 (5s timeout)
     * 2. Send JSON packet with END_MARKER
     * 3. Wait for ACK (5s timeout)
     * 4. Close connection
     *
     * @param targetIp IP address of the target node
     * @param packetJson JSON string to send
     * @return TransmissionResult indicating success or failure
     */
    suspend fun sendPacket(targetIp: String, packetJson: String): TransmissionResult {
        return withContext(Dispatchers.IO) {
            Log.d(TAG, "Sending packet to $targetIp (${packetJson.length} bytes)")
            
            var socket: Socket? = null
            
            try {
                // Create socket with timeout
                socket = Socket()
                val address = InetSocketAddress(targetIp, MESH_PORT)
                
                // STRICT 5-second connection timeout
                socket.connect(address, CONNECTION_TIMEOUT_MS)
                socket.soTimeout = READ_TIMEOUT_MS
                
                Log.d(TAG, "Connected to $targetIp")
                
                val outputStream = BufferedWriter(
                    OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8)
                )
                val inputStream = BufferedReader(
                    InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8)
                )
                
                // Send packet with end marker
                outputStream.write(packetJson)
                outputStream.write(END_MARKER)
                outputStream.flush()
                
                Log.d(TAG, "Packet sent to $targetIp, waiting for ACK")
                
                // Wait for ACK
                val ack = inputStream.readLine()
                
                if (ack == ACK_MESSAGE) {
                    Log.d(TAG, "Received ACK from $targetIp")
                    TransmissionResult.Success(targetIp)
                } else {
                    Log.w(TAG, "Unexpected response from $targetIp: $ack")
                    TransmissionResult.Failure(
                        targetIp,
                        TransmissionError.INVALID_ACK,
                        "Expected ACK, got: $ack"
                    )
                }
            } catch (e: SocketTimeoutException) {
                Log.e(TAG, "Connection timeout to $targetIp")
                TransmissionResult.Failure(
                    targetIp,
                    TransmissionError.TIMEOUT,
                    "Connection timed out after ${CONNECTION_TIMEOUT_MS}ms"
                )
            } catch (e: ConnectException) {
                Log.e(TAG, "Connection refused by $targetIp: ${e.message}")
                TransmissionResult.Failure(
                    targetIp,
                    TransmissionError.CONNECTION_REFUSED,
                    e.message ?: "Connection refused"
                )
            } catch (e: IOException) {
                Log.e(TAG, "IO error sending to $targetIp: ${e.message}")
                TransmissionResult.Failure(
                    targetIp,
                    TransmissionError.IO_ERROR,
                    e.message ?: "IO error"
                )
            } finally {
                // CRITICAL: Always close the connection immediately
                try {
                    socket?.close()
                } catch (e: IOException) {
                    // Ignore close errors
                }
                Log.d(TAG, "Connection to $targetIp closed")
            }
        }
    }

    /**
     * Checks if the server is currently running.
     */
    fun isServerRunning(): Boolean = serverSocket != null && !serverSocket!!.isClosed

    /**
     * Cleans up all resources.
     */
    fun cleanup() {
        stopServer()
        scope.cancel()
    }
}

/**
 * Result of a packet transmission attempt.
 */
sealed class TransmissionResult {
    abstract val targetIp: String
    
    data class Success(override val targetIp: String) : TransmissionResult()
    
    data class Failure(
        override val targetIp: String,
        val error: TransmissionError,
        val message: String
    ) : TransmissionResult()
    
    fun isSuccess(): Boolean = this is Success
}

/**
 * Types of transmission errors.
 */
enum class TransmissionError {
    TIMEOUT,
    CONNECTION_REFUSED,
    IO_ERROR,
    INVALID_ACK,
    UNKNOWN
}
