#!/usr/bin/env python3
"""Fix GO client IP resolution in ConnectionManager.kt:
1. Replace MAC-based ARP with MAC-free ARP (any 192.168.49.x != .1)
2. Expand subnet scan from .2-.20 to .2-.254 with parallel batches
3. Reduce DHCP settle time since ARP scan doesn't need MAC
"""
import sys

filepath = r'd:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt'

with open(filepath, 'rb') as f:
    content = f.read().decode('utf-8')

content = content.replace('\r\n', '\n')

# ---- Find the IP resolution block inside resolveClientIpFromGroup ----
# We replace the entire block from "scope.launch {" to the end of the launch block
# This is the section inside resolveClientIpFromGroup after targetClient is found

lines = content.split('\n')

# Find "scope.launch {" inside resolveClientIpFromGroup
resolve_func_start = None
scope_launch_line = None
scope_launch_end = None

for i, line in enumerate(lines):
    if 'private fun resolveClientIpFromGroup(' in line:
        resolve_func_start = i
    if resolve_func_start is not None and scope_launch_line is None:
        if line.strip() == 'scope.launch {' and i > resolve_func_start:
            scope_launch_line = i
            break

if scope_launch_line is None:
    print("ERROR: Could not find scope.launch in resolveClientIpFromGroup!")
    sys.exit(1)

# Find the matching closing brace of "scope.launch {"
# It's followed by two more closing braces (requestGroupInfo lambda, function)
brace_depth = 0
for i in range(scope_launch_line, len(lines)):
    for ch in lines[i]:
        if ch == '{':
            brace_depth += 1
        elif ch == '}':
            brace_depth -= 1
            if brace_depth == 0:
                scope_launch_end = i
                break
    if scope_launch_end is not None:
        break

if scope_launch_end is None:
    print("ERROR: Could not find matching brace for scope.launch!")
    sys.exit(1)

print(f"Found scope.launch block at lines {scope_launch_line+1}-{scope_launch_end+1}")

# Replace the entire scope.launch block with new IP resolution logic
new_launch_block = [
    '            scope.launch {',
    '                Log.d(TAG, "\\u23f3 Waiting ${DHCP_SETTLE_DELAY_MS}ms for client DHCP to settle...")',
    '                delay(DHCP_SETTLE_DELAY_MS)',
    '',
    '                // Step 1: Try MAC-based ARP lookup (works if MAC not randomized)',
    '                var clientIp = resolveIpFromArp(targetClient.deviceAddress)',
    '',
    '                // Step 2: MAC-free ARP - find any 192.168.49.x that is not .1 (us)',
    '                // P2P device MAC != P2P interface MAC (Android randomizes them)',
    '                if (clientIp == null) {',
    '                    Log.d(TAG, "\\U0001f504 MAC-based ARP failed, trying MAC-free ARP...")',
    '                    clientIp = resolveAnyP2pClientFromArp()',
    '                }',
    '',
    '                // Step 3: ARP retry with delay (DHCP may still be settling)',
    '                if (clientIp == null) {',
    '                    for (retryArp in 1..3) {',
    '                        Log.w(TAG, "\\u26a0\\ufe0f ARP miss, retrying in 2s (attempt $retryArp/3)...")',
    '                        delay(2000L)',
    '                        clientIp = resolveAnyP2pClientFromArp()',
    '                        if (clientIp != null) break',
    '                    }',
    '                }',
    '',
    '                // Step 4: Parallel subnet scan (.2 to .254)',
    '                if (clientIp == null) {',
    '                    clientIp = discoverP2pClientIp()',
    '                }',
    '',
    '                if (clientIp != null) {',
    '                    Log.d(TAG, "\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550")',
    '                    Log.d(TAG, "\\u2705 CONNECTED (GO mode) - Client IP: $clientIp")',
    '                    Log.d(TAG, "\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550\\u2550")',
    '                    withContext(Dispatchers.Main) {',
    '                        onConnected(clientIp)',
    '                    }',
    '                } else {',
    '                    Log.e(TAG, "\\u274c Could not resolve client IP from ARP table or subnet scan")',
    '                    withContext(Dispatchers.Main) {',
    '                        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {',
    '                            override fun onSuccess() { onFailure("Could not resolve client IP") }',
    '                            override fun onFailure(code: Int) { onFailure("Could not resolve client IP, cleanup failed") }',
    '                        })',
    '                    }',
    '                }',
    '            }',
]

lines[scope_launch_line:scope_launch_end+1] = new_launch_block
content = '\n'.join(lines)
print("Fix 1: Replaced IP resolution block with MAC-free ARP + retries")

# ---- Add resolveAnyP2pClientFromArp before resolveIpFromArp ----
old_marker = '    private fun resolveIpFromArp(macAddress: String): String? {'
new_with_fallback = '''    /**
     * MAC-free ARP lookup: find any P2P client in 192.168.49.x subnet.
     * P2P device address (WifiP2pDevice.deviceAddress) is NOT the same as
     * the interface MAC visible in ARP table. Android randomizes P2P MACs.
     * Since we are GO (192.168.49.1), any other 192.168.49.x is our client.
     */
    private fun resolveAnyP2pClientFromArp(): String? {
        try {
            val arpTable = java.io.File("/proc/net/arp").readText()
            Log.d(TAG, "\U0001f4cb ARP table:\\n$arpTable")

            for (line in arpTable.lines()) {
                val parts = line.trim().split("\\\\s+".toRegex())
                val ip = parts.firstOrNull() ?: continue
                if (ip.startsWith("192.168.49.") && ip != "192.168.49.1") {
                    Log.d(TAG, "\\u2705 Found P2P client IP from ARP (MAC-free): $ip")
                    return ip
                }
            }
            Log.w(TAG, "\\u26a0\\ufe0f No P2P client found in ARP table")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "\\u274c Error reading ARP table: ${e.message}")
            return null
        }
    }

    private fun resolveIpFromArp(macAddress: String): String? {'''

if old_marker in content:
    content = content.replace(old_marker, new_with_fallback, 1)
    print("Fix 2: Added resolveAnyP2pClientFromArp() method")
else:
    print("ERROR: Could not find resolveIpFromArp!")
    sys.exit(1)

# ---- Replace subnet scan with parallel version (.2-.254) ----
lines = content.split('\n')
scan_start = None
scan_end = None

for i, line in enumerate(lines):
    if 'private suspend fun discoverP2pClientIp()' in line:
        scan_start = i
        break

if scan_start is not None:
    brace_depth = 0
    found_first_brace = False
    for i in range(scan_start, len(lines)):
        for ch in lines[i]:
            if ch == '{':
                brace_depth += 1
                found_first_brace = True
            elif ch == '}':
                brace_depth -= 1
                if found_first_brace and brace_depth == 0:
                    scan_end = i
                    break
        if scan_end is not None:
            break

if scan_start is None or scan_end is None:
    print(f"ERROR: Could not find discoverP2pClientIp! start={scan_start} end={scan_end}")
    sys.exit(1)

print(f"Found discoverP2pClientIp at lines {scan_start+1}-{scan_end+1}")

new_scan = [
    '    private suspend fun discoverP2pClientIp(): String? {',
    '        return withContext(Dispatchers.IO) {',
    '            Log.d(TAG, "\\U0001f50d Starting parallel subnet scan (192.168.49.2-254)...")',
    '            // Parallel batches of 25 with 500ms timeout each',
    '            val batchSize = 25',
    '            for (batchStart in 2..254 step batchSize) {',
    '                val batchEnd = minOf(batchStart + batchSize - 1, 254)',
    '                val deferreds = (batchStart..batchEnd).map { i ->',
    '                    async {',
    '                        val candidateIp = "192.168.49.$i"',
    '                        try {',
    '                            val addr = java.net.InetAddress.getByName(candidateIp)',
    '                            if (addr.isReachable(500)) candidateIp else null',
    '                        } catch (e: Exception) {',
    '                            null',
    '                        }',
    '                    }',
    '                }',
    '                val results = deferreds.mapNotNull { it.await() }',
    '                if (results.isNotEmpty()) {',
    '                    Log.d(TAG, "\\u2705 Found reachable P2P client at ${results.first()} (parallel subnet scan)")',
    '                    return@withContext results.first()',
    '                }',
    '            }',
    '            Log.w(TAG, "\\u26a0\\ufe0f No P2P client found in subnet scan (2-254)")',
    '            null',
    '        }',
    '    }',
]

lines[scan_start:scan_end+1] = new_scan
content = '\n'.join(lines)
print("Fix 3: Replaced subnet scan with parallel version (2-254)")

# Write back
with open(filepath, 'wb') as f:
    f.write(content.encode('utf-8'))

print("\nAll GO IP resolution fixes applied successfully!")
