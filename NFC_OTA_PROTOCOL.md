# NFC OTA Firmware Update Protocol

This document describes the EEPROM-based OTA (Over-The-Air) firmware update protocol used between the Flutter app and ESP32 via the ST25DV NFC tag.

## Overview

The protocol uses the ST25DV EEPROM memory (not the mailbox/FTM) to transfer firmware data in chunks. This is similar to the existing sensor data transfer protocol, providing reliable communication through polling-based handshaking.

## Memory Map

| Address | Size | Name | Description |
|---------|------|------|-------------|
| 0x78 | 4 bytes | `NFC_OTA_CMD_ADDR` | Command field (written by app) |
| 0x7C | 4 bytes | `NFC_OTA_STATUS_ADDR` | Status field (written by ESP32) |
| 0x80 | 4 bytes | `NFC_OTA_CHUNK_NUM_ADDR` | Current chunk number (0-indexed) |
| 0x84 | 4 bytes | `NFC_OTA_TOTAL_SIZE_ADDR` | Total firmware size in bytes |
| 0x88 | 4 bytes | `NFC_OTA_CHUNK_SIZE_ADDR` | Current chunk size in bytes |
| 0x8C | 4 bytes | `NFC_OTA_CRC32_ADDR` | CRC32 of current chunk data |
| 0xC8 | variable | `NFC_OTA_DATA_ADDR` | Firmware chunk data (max 1800 bytes) |

> **Note:** All multi-byte values are stored in **little-endian** format.

## Commands (App → ESP32)

Written to `NFC_OTA_CMD_ADDR` (0x78):

| Command | Value (hex) | ASCII | Description |
|---------|-------------|-------|-------------|
| `NFC_OTA_CMD_NONE` | 0x00000000 | - | Idle / No command |
| `NFC_OTA_CMD_START` | 0x4F544153 | 'SATO' | Start OTA transfer |
| `NFC_OTA_CMD_DATA` | 0x4F544144 | 'DATO' | Data chunk ready for processing |
| `NFC_OTA_CMD_END` | 0x4F544145 | 'EATO' | End of transfer, finalize update |
| `NFC_OTA_CMD_ABORT` | 0x4F544158 | 'XATO' | Abort transfer |

> **Note:** ASCII shown is reversed due to little-endian storage. In memory: 'OTAS', 'OTAD', 'OTAE', 'OTAX'.

## Status Codes (ESP32 → App)

Written to `NFC_OTA_STATUS_ADDR` (0x7C):

| Status | Value (hex) | ASCII | Description |
|--------|-------------|-------|-------------|
| `NFC_OTA_STATUS_IDLE` | 0x00000000 | - | Idle state |
| `NFC_OTA_STATUS_READY` | 0x4F545259 | 'YRTO' | Ready for next chunk |
| `NFC_OTA_STATUS_BUSY` | 0x4F544259 | 'YBTO' | Currently processing |
| `NFC_OTA_STATUS_ERROR` | 0x4F544552 | 'RETO' | Error occurred |
| `NFC_OTA_STATUS_DONE` | 0x4F54444E | 'NDTO' | OTA complete, rebooting |

> **Note:** In memory: 'OTRY', 'OTBY', 'OTER', 'OTDN'.

## Protocol Flow

### 1. Start Transfer

```
App                                 ESP32
 |                                    |
 |-- Write total_size to 0x84 ------->|
 |-- Write chunk_num=0 to 0x80 ------>|
 |-- Write CMD_START to 0x78 -------->|
 |                                    |
 |<--- Poll STATUS at 0x7C -----------|
 |     (wait for STATUS_READY)        |
 |                                    |
```

**ESP32 actions on CMD_START:**
1. Read total firmware size from `NFC_OTA_TOTAL_SIZE_ADDR`
2. Initialize OTA partition
3. Allocate buffers
4. Write `STATUS_READY` to indicate ready for first chunk

### 2. Send Chunks

Repeat for each chunk (chunk_num = 0, 1, 2, ...):

```
App                                 ESP32
 |                                    |
 |-- Write chunk_num to 0x80 -------->|
 |-- Write chunk_size to 0x88 ------->|
 |-- Write crc32 to 0x8C ------------>|
 |-- Write chunk_data to 0xC8 ------->|
 |-- Write CMD_DATA to 0x78 --------->|
 |                                    |
 |<--- Poll STATUS at 0x7C -----------|
 |     (wait for STATUS_READY)        |
 |                                    |
```

**ESP32 actions on CMD_DATA:**
1. Read chunk metadata (chunk_num, chunk_size, expected CRC32)
2. Read chunk data from `NFC_OTA_DATA_ADDR`
3. Verify CRC32 matches
4. Write chunk to OTA partition
5. If CRC mismatch: write `STATUS_ERROR`
6. If success: write `STATUS_READY`

### 3. End Transfer

```
App                                 ESP32
 |                                    |
 |-- Write CMD_END to 0x78 ---------->|
 |                                    |
 |<--- Poll STATUS at 0x7C -----------|
 |     (wait for STATUS_DONE)         |
 |                                    |
 |                              [REBOOT]
```

**ESP32 actions on CMD_END:**
1. Finalize OTA partition
2. Validate complete firmware
3. Set boot partition to new firmware
4. Write `STATUS_DONE`
5. Reboot

## Chunk Size

- **Maximum chunk size:** 1800 bytes (`NFC_OTA_MAX_CHUNK_SIZE`)
- The last chunk may be smaller than 1800 bytes
- Total chunks = ceil(firmware_size / 1800)

## CRC32 Calculation

Standard CRC32 algorithm with polynomial `0xEDB88320`:

```c
uint32_t calculate_crc32(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    return crc ^ 0xFFFFFFFF;
}
```

## Timing

- **Polling interval:** 100ms
- **Chunk processing timeout:** 20 seconds (200 polls)
- **Start/End timeout:** 10 seconds (100 polls)

## Error Handling

### App-side
- If `STATUS_ERROR` received: abort and show error message
- If timeout waiting for status: abort and show timeout error
- If NFC connection lost: show reconnect message

### ESP32-side
- If CRC mismatch: write `STATUS_ERROR` (app should abort)
- If write to flash fails: write `STATUS_ERROR`
- If invalid chunk number: write `STATUS_ERROR`

## Example ESP32 Implementation (Pseudocode)

```c
void nfc_ota_task(void) {
    while (1) {
        uint32_t cmd = read_nfc_u32(NFC_OTA_CMD_ADDR);
        
        switch (cmd) {
            case NFC_OTA_CMD_START:
                total_size = read_nfc_u32(NFC_OTA_TOTAL_SIZE_ADDR);
                if (ota_begin(total_size) == OK) {
                    expected_chunk = 0;
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_READY);
                } else {
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_ERROR);
                }
                write_nfc_u32(NFC_OTA_CMD_ADDR, NFC_OTA_CMD_NONE);
                break;
                
            case NFC_OTA_CMD_DATA:
                chunk_num = read_nfc_u32(NFC_OTA_CHUNK_NUM_ADDR);
                chunk_size = read_nfc_u32(NFC_OTA_CHUNK_SIZE_ADDR);
                expected_crc = read_nfc_u32(NFC_OTA_CRC32_ADDR);
                
                read_nfc_data(NFC_OTA_DATA_ADDR, buffer, chunk_size);
                actual_crc = calculate_crc32(buffer, chunk_size);
                
                if (actual_crc != expected_crc) {
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_ERROR);
                } else if (ota_write(buffer, chunk_size) == OK) {
                    expected_chunk++;
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_READY);
                } else {
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_ERROR);
                }
                write_nfc_u32(NFC_OTA_CMD_ADDR, NFC_OTA_CMD_NONE);
                break;
                
            case NFC_OTA_CMD_END:
                if (ota_end() == OK) {
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_DONE);
                    vTaskDelay(100 / portTICK_PERIOD_MS);
                    esp_restart();
                } else {
                    write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_ERROR);
                }
                break;
                
            case NFC_OTA_CMD_ABORT:
                ota_abort();
                write_nfc_u32(NFC_OTA_STATUS_ADDR, NFC_OTA_STATUS_IDLE);
                write_nfc_u32(NFC_OTA_CMD_ADDR, NFC_OTA_CMD_NONE);
                break;
        }
        
        vTaskDelay(50 / portTICK_PERIOD_MS);
    }
}
```

## Constants Header File

```c
// NFC OTA Protocol addresses
#define NFC_OTA_CMD_ADDR        0x78  // Command field
#define NFC_OTA_STATUS_ADDR     0x7C  // Status field
#define NFC_OTA_CHUNK_NUM_ADDR  0x80  // Current chunk number
#define NFC_OTA_TOTAL_SIZE_ADDR 0x84  // Total firmware size
#define NFC_OTA_CHUNK_SIZE_ADDR 0x88  // Current chunk size
#define NFC_OTA_CRC32_ADDR      0x8C  // CRC32 of chunk
#define NFC_OTA_DATA_ADDR       0xC8  // Data payload start

// OTA Commands (app -> ESP32)
#define NFC_OTA_CMD_NONE   0x00000000
#define NFC_OTA_CMD_START  0x4F544153  // 'OTAS'
#define NFC_OTA_CMD_DATA   0x4F544144  // 'OTAD'
#define NFC_OTA_CMD_END    0x4F544145  // 'OTAE'
#define NFC_OTA_CMD_ABORT  0x4F544158  // 'OTAX'

// OTA Status (ESP32 -> app)
#define NFC_OTA_STATUS_IDLE  0x00000000
#define NFC_OTA_STATUS_READY 0x4F545259  // 'OTRY'
#define NFC_OTA_STATUS_BUSY  0x4F544259  // 'OTBY'
#define NFC_OTA_STATUS_ERROR 0x4F544552  // 'OTER'
#define NFC_OTA_STATUS_DONE  0x4F54444E  // 'OTDN'

// Chunk size
#define NFC_OTA_MAX_CHUNK_SIZE 1800
```
