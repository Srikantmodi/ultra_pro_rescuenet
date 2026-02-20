#!/usr/bin/env python3
"""Fix the misplaced scope.launch in ConnectionManager.kt:
1. Restore first scope.launch (retry block) to original simple form
2. Replace second scope.launch (IP resolution) with MAC-free ARP logic
"""
import sys

filepath = r'd:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt'

with open(filepath, 'rb') as f:
    content = f.read().decode('utf-8')

content = content.replace('\r\n', '\n')
lines = content.split('\n')

print(f"Total lines: {len(lines)}")

# ---- STEP 1: Find and fix the FIRST scope.launch (wrongly replaced) ----
# Pattern: after "Group info null, retrying" log line, there should be a simple
# scope.launch { delay; retry } but instead has the full IP resolution code.

# Find the line with "Group info null, retrying"
group_null_retry_line = None
for i, line in enumerate(lines):
    if 'Group info null, retrying' in line:
        group_null_retry_line = i
        break

if group_null_retry_line is None:
    print("ERROR: Could not find 'Group info null, retrying' line")
    sys.exit(1)

print(f"Found 'Group info null, retrying' at line {group_null_retry_line + 1}")

# The next line should be "scope.launch {" - find the misplaced big block
first_scope_line = group_null_retry_line + 1
# Find the closing "}" of this scope.launch - it's followed by "} else {"
# We need to find the matching brace depth.
brace_depth = 0
first_scope_end = None
for i in range(first_scope_line, len(lines)):
    for ch in lines[i]:
        if ch == '{':
            brace_depth += 1
        elif ch == '}':
            brace_depth -= 1
            if brace_depth == 0:
                first_scope_end = i
                break
    if first_scope_end is not None:
        break

print(f"First scope.launch block: lines {first_scope_line + 1} to {first_scope_end + 1}")

# Replace the big block with the simple retry
new_first_scope = [
    '                    scope.launch {',
    '                        delay(CONNECTION_RETRY_DELAY_MS)',
    '                        resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure, attempt + 1)',
    '                    }',
]

lines[first_scope_line:first_scope_end + 1] = new_first_scope
content = '\n'.join(lines)
print("Step 1: Restored first scope.launch to simple retry block")

# ---- STEP 2: Find and fix the SECOND scope.launch (actual IP resolution) ----
# Re-split after modification
lines = content.split('\n')

# Find the second scope.launch that's in the "targetClient found" branch
# It's after "val targetClient = clients.firstOrNull..."
target_client_line = None
for i, line in enumerate(lines):
    if 'val targetClient = clients.firstOrNull' in line:
        target_client_line = i
        break

if target_client_line is None:
    print("ERROR: Could not find 'val targetClient' line")
    sys.exit(1)

print(f"Found 'val targetClient' at line {target_client_line + 1}")

# Find the scope.launch after targetClient
second_scope_line = None
for i in range(target_client_line, min(target_client_line + 10, len(lines))):
    if 'scope.launch' in lines[i]:
        second_scope_line = i
        break

if second_scope_line is None:
    print("ERROR: Could not find second scope.launch after targetClient")
    sys.exit(1)

# Find matching closing brace
brace_depth = 0
second_scope_end = None
for i in range(second_scope_line, len(lines)):
    for ch in lines[i]:
        if ch == '{':
            brace_depth += 1
        elif ch == '}':
            brace_depth -= 1
            if brace_depth == 0:
                second_scope_end = i
                break
    if second_scope_end is not None:
        break

print(f"Second scope.launch block: lines {second_scope_line + 1} to {second_scope_end + 1}")

# Replace with new MAC-free ARP resolution logic
new_second_scope = [
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

lines[second_scope_line:second_scope_end + 1] = new_second_scope
content = '\n'.join(lines)
print("Step 2: Replaced second scope.launch with MAC-free ARP resolution logic")

# Write back
with open(filepath, 'wb') as f:
    f.write(content.encode('utf-8'))

print(f"\nDone! File now has {len(content.split(chr(10)))} lines")
print("All fixes applied successfully!")
