# NFC + BLE OTA Firmware Update Protocol

This document describes the hybrid NFC/BLE OTA (Over-The-Air) firmware update protocol used between the Flutter app and ESP32 via the ST25DV NFC tag and Bluetooth Low Energy.

## Overview

The app writes a single NFC command to the ST25DV EEPROM telling the ESP32 to enable its BLE radio. The ESP32 then advertises a BLE GATT OTA service, and the app automatically discovers and connects to it to transfer the firmware. This is much faster than pure NFC EEPROM transfer.

## Update Flow

```
┌─────────┐         ┌──────────┐         ┌─────────┐
│   App   │         │ ST25DV   │         │  ESP32  │
│ (Phone) │         │ (EEPROM) │         │         │
└────┬────┘         └────┬─────┘         └────┬────┘
     │                   │                    │
     │  1. Write         │                    │
     │  NFC_OTA_CMD_BLE  │                    │
     │  to 0x78          │                    │
     │──────────────────>│                    │
     │                   │  2. ESP32 polls    │
     │                   │  and reads cmd     │
     │                   │<───────────────────│
     │                   │                    │
     │                   │  3. ESP32 enables  │
     │                   │  BLE (up to 5 min) │
     │                   │                    │
     │  4. App scans for BLE OTA service      │
     │  (service UUID: 4FAFC201-...)          │
     │<───────────────── BLE Advertisement ───│
     │                                        │
     │  5. App connects via BLE               │
     │───────────────────────────────────────>│
     │                                        │
     │  6. Send START cmd (size)              │
     │───────────────────────────────────────>│
     │                                        │
     │  7. Stream firmware data chunks        │
     │═══════════════════════════════════════>│
     │                                        │
     │  8. Send END cmd                       │
     │───────────────────────────────────────>│
     │                                        │
     │  9. DONE notification                  │
     │<───────────────────────────────────────│
     │                                   [REBOOT]
```

## Step 1: NFC Trigger

The app writes a single 4-byte command to EEPROM address `0x78`:

| Address | Size | Value | ASCII | Description |
|---------|------|-------|-------|-------------|
| 0x78 | 4 bytes | `0x4F544142` | 'OTAB' | Enable BLE for OTA update |

After writing, the phone can be moved away from the NFC tag. The ESP32 polls this address and, upon seeing the command, enables its BLE radio and starts advertising the OTA service.

**Note:** The ESP32 may take **up to 5 minutes** to enable BLE after the command is written, depending on its current power state and polling interval.

## Step 2: BLE Discovery & Connection

The app automatically scans for a BLE device advertising the OTA service UUID. No user interaction is required.

### BLE UUIDs

| UUID | Name | Description |
|------|------|-------------|
| `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` | OTA Service | Main OTA service |
| `D5875408-FA51-4763-A75D-7D33CECEBC31` | OTA Control | Control characteristic (write + notify) |
| `BEB5483E-36E1-4688-B7F5-EA07361B26A8` | OTA Data | Firmware data characteristic (write without response) |

### BLE Control Commands (App → ESP32)

Written to the **OTA Control** characteristic:

| Command | Byte(s) | Description |
|---------|---------|-------------|
| START | `0x01` + 4 bytes (LE firmware size) | Start OTA, total size follows |
| END | `0x02` | All data sent, verify & apply |
| ABORT | `0x03` | Cancel the update |

### BLE Status Notifications (ESP32 → App)

Sent via notifications on the **OTA Control** characteristic:

| Status | Byte | Description |
|--------|------|-------------|
| READY | `0x01` | Ready for data / start acknowledged |
| ERROR | `0x02` | Error occurred (may include error code in byte 2) |
| DONE | `0x03` | Firmware verified, rebooting |

## Step 3: Firmware Transfer

1. App sends **START** command with firmware size via the control characteristic
2. App waits for **READY** notification
3. App streams firmware binary in MTU-sized chunks via the data characteristic (write without response)
4. App sends **END** command via the control characteristic
5. ESP32 verifies the firmware, writes to flash, and sends **DONE** notification
6. ESP32 reboots

### MTU & Chunk Size

- App requests MTU of 512 bytes
- Actual chunk size = negotiated MTU − 3 (ATT overhead)
- Typical chunk size: 244–509 bytes (much faster than NFC's 4 bytes/block)

## Timing

| Parameter | Value |
|-----------|-------|
| BLE scan timeout | 5 minutes |
| BLE connection timeout | 15 seconds |
| START acknowledgment timeout | 10 seconds |
| END/DONE timeout | 30 seconds |
| Inter-chunk delay | 10ms every 20 chunks |

## Error Handling

### App-side
- If BLE device not found within 5 minutes: show timeout, suggest retry
- If BLE connection drops: show error, clean up
- If ERROR notification received: abort and show error message
- If DONE timeout: show verification error

### ESP32-side
- If firmware verification fails: send ERROR notification
- If flash write fails: send ERROR notification
- After DONE: reboot to new firmware

## ESP32 Implementation Notes

### NFC Polling
```c
// In the main NFC polling loop:
uint32_t cmd = read_nfc_u32(NFC_OTA_CMD_ADDR);  // 0x78
if (cmd == 0x4F544142) {  // 'OTAB'
    // Clear the command
    write_nfc_u32(NFC_OTA_CMD_ADDR, 0x00000000);
    // Enable BLE and start advertising OTA service
    start_ble_ota_server();
}
```

### BLE GATT Server
```c
// Service: 4FAFC201-1FB5-459E-8FCC-C5C9C331914B
// Control char: D5875408-FA51-4763-A75D-7D33CECEBC31  (write + notify)
// Data char:    BEB5483E-36E1-4688-B7F5-EA07361B26A8  (write no response)

void on_control_write(uint8_t *data, uint16_t len) {
    if (data[0] == 0x01 && len >= 5) {
        // START: extract firmware size (LE 4 bytes)
        uint32_t size = data[1] | (data[2]<<8) | (data[3]<<16) | (data[4]<<24);
        ota_begin(size);
        notify_control(0x01);  // READY
    } else if (data[0] == 0x02) {
        // END: verify and apply
        if (ota_end() == OK) {
            notify_control(0x03);  // DONE
            reboot();
        } else {
            notify_control(0x02);  // ERROR
        }
    } else if (data[0] == 0x03) {
        // ABORT
        ota_abort();
    }
}

void on_data_write(uint8_t *data, uint16_t len) {
    ota_write(data, len);
}
```

## Constants Header File

```c
// NFC OTA trigger address (EEPROM)
#define NFC_OTA_CMD_ADDR         0x78       // Command field
#define NFC_OTA_CMD_NONE         0x00000000 // No command
#define NFC_OTA_CMD_BLE_ENABLE   0x4F544142 // 'OTAB' - Enable BLE for OTA

// BLE OTA Service and Characteristic UUIDs
// Service:  4FAFC201-1FB5-459E-8FCC-C5C9C331914B
// Control:  D5875408-FA51-4763-A75D-7D33CECEBC31
// Data:     BEB5483E-36E1-4688-B7F5-EA07361B26A8

// BLE OTA Control Commands (app -> ESP32)
#define BLE_OTA_CTRL_START  0x01
#define BLE_OTA_CTRL_END    0x02
#define BLE_OTA_CTRL_ABORT  0x03

// BLE OTA Status Notifications (ESP32 -> app)
#define BLE_OTA_STATUS_READY  0x01
#define BLE_OTA_STATUS_ERROR  0x02
#define BLE_OTA_STATUS_DONE   0x03
```

## Migration from Pure NFC OTA

The previous protocol transferred firmware entirely over NFC EEPROM in 1800-byte chunks, which was very slow. The new protocol:

- Uses NFC only for a **single 4-byte trigger write**
- Transfers firmware data over **BLE** (orders of magnitude faster)
- Requires no user interaction for BLE pairing/selection
- Phone can be moved away from the device after the NFC tap
