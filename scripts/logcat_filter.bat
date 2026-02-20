@echo off
REM ============================================================
REM RescueNet Pro — ADB Logcat Filter Script
REM ============================================================
REM Usage:
REM   logcat_filter.bat              -- uses first connected device
REM   logcat_filter.bat DEVICE_ID    -- targets specific device
REM ============================================================

SET DEVICE=%1

IF "%DEVICE%"=="" (
    echo No device serial specified, using first connected device...
    adb logcat -v time WifiP2pHandler:D ConnectionManager:D SocketServer:D MeshService:D RelayOrchestrator:D flutter:I *:S
) ELSE (
    echo Filtering logs for device: %DEVICE%
    adb -s %DEVICE% logcat -v time WifiP2pHandler:D ConnectionManager:D SocketServer:D MeshService:D RelayOrchestrator:D flutter:I *:S
)
