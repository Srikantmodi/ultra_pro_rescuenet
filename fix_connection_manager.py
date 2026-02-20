#!/usr/bin/env python3
"""Fix ConnectionManager.kt:
1. String interpolation bug: ${'$'}{ -> ${
2. Add PEER_REDISCOVERY_DELAY_MS constant
3. Replace retry cleanup: removeGroup -> discoverPeers
"""
import sys

filepath = r'd:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt'

with open(filepath, 'rb') as f:
    content = f.read().decode('utf-8')

# Normalize line endings
content = content.replace('\r\n', '\n')

# ---- Fix 1: String interpolation bug ----
# In Kotlin, ${'$'} produces a literal $ character.
# We want actual string template interpolation: ${variable}
old_interp = "${'$'}{"
new_interp = "${"
count1 = content.count(old_interp)
content = content.replace(old_interp, new_interp)
print(f"Fix 1: Replaced {count1} string interpolation escapes")

# ---- Fix 2: Add PEER_REDISCOVERY_DELAY_MS constant ----
old_const = "private const val CONNECT_RETRY_DELAY_MS = 2000L"
new_const = "private const val CONNECT_RETRY_DELAY_MS = 2000L\n        private const val PEER_REDISCOVERY_DELAY_MS = 3500L"
if old_const in content:
    content = content.replace(old_const, new_const, 1)
    print("Fix 2: Added PEER_REDISCOVERY_DELAY_MS constant")
else:
    print("ERROR: Could not find CONNECT_RETRY_DELAY_MS constant!")
    sys.exit(1)

# ---- Fix 3: Replace retry cleanup logic ----
# Use line-based approach to avoid emoji matching issues
lines = content.split('\n')

# Find start: line containing "cleaning up before retry..."
start_idx = None
for i, line in enumerate(lines):
    if 'cleaning up before retry...' in line:
        start_idx = i
        break

# Find end: the closing }) of the removeGroup ActionListener
# It's after the "retrying anyway" line
end_idx = None
if start_idx is not None:
    for i in range(start_idx, min(start_idx + 30, len(lines))):
        if 'retrying anyway' in lines[i]:
            # Look for the closing }) after retryAction() call
            for j in range(i + 1, min(i + 5, len(lines))):
                stripped = lines[j].strip()
                if stripped == '})':
                    end_idx = j
                    break
            break

if start_idx is None or end_idx is None:
    print(f"ERROR: Could not find retry block. start={start_idx}, end={end_idx}")
    sys.exit(1)

print(f"Fix 3: Found retry block at lines {start_idx+1}-{end_idx+1}")

# New retry lines (using discoverPeers instead of removeGroup)
new_retry_lines = [
    '                    Log.w(TAG, "\u26a0\ufe0f connect() returned $errorMsg (attempt $connectAttempt/$MAX_CONNECT_RETRIES)")',
    '                    Log.d(TAG, "\U0001f504 Refreshing peer discovery before retry...")',
    '',
    '                    // When connect() returns ERROR, the peer is likely absent from',
    "                    // the framework's discovered peer cache (cleared after disconnect).",
    '                    // Trigger discoverPeers() to refresh the cache before retrying.',
    '                    manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {',
    '                        override fun onSuccess() {',
    '                            Log.d(TAG, "\u2705 Peer discovery refresh triggered")',
    '                        }',
    '                        override fun onFailure(code2: Int) {',
    '                            Log.w(TAG, "\u26a0\ufe0f Peer discovery refresh failed: ${getErrorMessage(code2)}")',
    '                        }',
    '                    })',
    '',
    '                    scope.launch {',
    '                        delay(PEER_REDISCOVERY_DELAY_MS)',
    '                        withContext(Dispatchers.Main) {',
    '                            initiateConnection(deviceAddress, onConnected, onFailure, connectAttempt + 1)',
    '                        }',
    '                    }',
]

lines[start_idx:end_idx+1] = new_retry_lines
content = '\n'.join(lines)
print(f"Fix 3: Replaced retry cleanup logic (removeGroup -> discoverPeers)")

# Write back
with open(filepath, 'wb') as f:
    f.write(content.encode('utf-8'))

print("\nAll fixes applied successfully!")
