
# Fix the ending: close doConnect lambda and add stopPeerDiscovery block
$handlerFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\WifiP2pHandler.kt"
$handler = [System.IO.File]::ReadAllText($handlerFile, [System.Text.Encoding]::UTF8)

# Find the closing of connectionManager.connect() followed by the method closing
# Pattern: "            }\n        )\n    }\n" near the end of connectAndSendPacket
# The context before is: result.error("CONNECTION_FAILED", error, null)

$oldEnding = '            }
        )
    }

    /**
     * FIX D-5: Restart service discovery after a connect-and-send cycle.'

$newEnding = '            }
        )
        }

        // FIX GROUP-FORM: Pause service discovery before connecting.
        // Android''s P2P driver on many devices cannot handle concurrent
        // discoverServices() and GO negotiation -- the negotiation silently
        // fails and the group never forms. Stopping discovery first frees
        // the driver to focus on the connection handshake.
        // Discovery is restarted by restartDiscoveryAfterSend() after
        // the send completes (success or failure).
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Discovery paused for connection attempt")
                doConnect()
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "stopPeerDiscovery failed (code: $code), proceeding anyway")
                doConnect()
            }
        })
    }

    /**
     * FIX D-5: Restart service discovery after a connect-and-send cycle.'

if ($handler.Contains($oldEnding)) {
    $handler = $handler.Replace($oldEnding, $newEnding)
    [System.IO.File]::WriteAllText($handlerFile, $handler, [System.Text.Encoding]::UTF8)
    Write-Host "SUCCESS: doConnect lambda closed + stopPeerDiscovery block added"
} else {
    Write-Host "WARNING: Old ending pattern not found. Trying without FIX D-5 context..."
    
    # Try a simpler pattern match
    # Look for the specific sequence after the onFailure block
    # Find "        )\n    }\n" that's the last occurrence (end of connectAndSendPacket)
    
    # Let's try a broader pattern
    $pattern = '                    result.error("CONNECTION_FAILED", error, null)
                }
            }
        )
    }'
    
    $replacement = '                    result.error("CONNECTION_FAILED", error, null)
                }
            }
        )
        }

        // FIX GROUP-FORM: Pause service discovery before connecting.
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Discovery paused for connection attempt")
                doConnect()
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "stopPeerDiscovery failed (code: $code), proceeding anyway")
                doConnect()
            }
        })
    }'

    if ($handler.Contains($pattern)) {
        $handler = $handler.Replace($pattern, $replacement)
        [System.IO.File]::WriteAllText($handlerFile, $handler, [System.Text.Encoding]::UTF8)
        Write-Host "SUCCESS (alt pattern): doConnect lambda closed + stopPeerDiscovery block added"
    } else {
        Write-Host "FAILED: Could not find ending pattern. Dumping lines 695-715 for debug:"
        $lines = $handler.Split("`n")
        for ($i = 694; $i -lt [Math]::Min(715, $lines.Length); $i++) {
            Write-Host ("Line " + ($i+1) + ": [" + $lines[$i] + "]")
        }
    }
}
