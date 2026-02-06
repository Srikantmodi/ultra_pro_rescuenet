package com.example.ultra_pro_rescuenet

import android.os.AsyncTask
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class SocketHandler : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val SERVER_PORT = 8888
    private var serverThread: Thread? = null
    private var isRunning = false
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    
    private var eventSink: EventChannel.EventSink? = null
    
    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, "com.rescuenet/wifi_p2p/socket")
        methodChannel.setMethodCallHandler(this)
        
        val eventChannel = EventChannel(messenger, "com.rescuenet/wifi_p2p/packets")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startServer" -> {
                startServer()
                result.success(null)
            }
            "stopServer" -> {
                stopServer()
                result.success(null)
            }
            "sendPacket" -> {
                val targetAddress = call.argument<String>("targetAddress")
                val packetJson = call.argument<String>("packetJson")
                if (targetAddress != null && packetJson != null) {
                    sendPacket(targetAddress, packetJson, result)
                } else {
                    result.error("INVALID_ARGS", "Missing target or packet", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun startServer() {
        if (isRunning) return
        isRunning = true
        serverThread = Thread {
            try {
                val serverSocket = ServerSocket(SERVER_PORT)
                Log.d("SocketHandler", "Server started on $SERVER_PORT")
                
                while (isRunning) {
                    val client = serverSocket.accept()
                    handleClient(client)
                }
                serverSocket.close()
            } catch (e: Exception) {
                Log.e("SocketHandler", "Server error", e)
                isRunning = false
            }
        }
        serverThread?.start()
    }
    
    fun stopServer() {
        isRunning = false
        // Trigger generic socket close if needed or let thread die naturally on next accept failure (if implemented with timeout)
        // For simple implementation, we assume restarting app clears this or we just leave it. 
        // interrupting might be needed.
        serverThread?.interrupt()
    }

    private fun handleClient(client: Socket) {
        executor.execute {
            try {
                val reader = BufferedReader(InputStreamReader(client.getInputStream()))
                // Read content. Expecting one line of JSON for now.
                val json = reader.readLine()
                if (json != null) {
                    val event = mapOf(
                        "type" to "packetReceived",
                        "packet" to json,
                        "senderIp" to (client.inetAddress.hostAddress ?: "")
                    )
                    Handler(Looper.getMainLooper()).post {
                        eventSink?.success(event)
                    }
                    // Send ACK
                    val writer = PrintWriter(client.getOutputStream(), true)
                    writer.println("ACK")
                }
                client.close()
            } catch (e: Exception) {
                Log.e("SocketHandler", "Client handle error", e)
            }
        }
    }

    private fun sendPacket(targetAddress: String, json: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                val success = sendPacketInternal(targetAddress, json)
                Handler(Looper.getMainLooper()).post {
                    result.success(success)
                }
            } catch (e: Exception) {
                Log.e("SocketHandler", "Send error to $targetAddress", e)
                Handler(Looper.getMainLooper()).post {
                    result.success(false) 
                }
            }
        }
    }

    // NEW: Synchronous send packet (for GeneralHandler)
    fun sendPacketSync(targetAddress: String, json: String): Boolean {
        return try {
            sendPacketInternal(targetAddress, json)
        } catch (e: Exception) {
            Log.e("SocketHandler", "Sync send error", e)
            false
        }
    }

    private fun sendPacketInternal(targetAddress: String, json: String): Boolean {
        val socket = Socket()
        socket.connect(InetSocketAddress(targetAddress, SERVER_PORT), 5000)
        val writer = PrintWriter(socket.getOutputStream(), true)
        writer.println(json)
        
        // Wait for ACK
        socket.soTimeout = 5000
        val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
        val ack = reader.readLine()
        
        socket.close()
        return ack == "ACK"
    }
}
