import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart' as nfc;
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart' as ndef;
import 'package:nfc_manager/nfc_manager_android.dart' as android;
// import 'package:nfc_manager/nfc_manager_ios.dart' as ios;
import 'dart:typed_data';
import 'dart:convert';
import 'package:nfc_manager/ndef_record.dart' as ndefrec;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teka Dust Sensor',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'TEKA Dust Sensor'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _nfcStatus = 'Tap "Start NFC Scan" and touch the ST25DV tag.';
  String? _eepromData;
  bool _scanning = false;
  // Memory map (byte offsets)
  static const int MEM_VAL_MEASURE_MODE = 16; // 4 bytes (block 4)
  static const int MEM_VAL_USER_NAME_LENGTH = 44; // 4 bytes (block 11)
  static const int MEM_VAL_USER_NAME = 48; // 30 bytes (blocks 12..19)

  // Config fields
  String _userName = '';
  int _measureMode = 0; // 0 or 1

  @override
  void initState() {
    super.initState();
    _loadConfigFromStorage();
  }

  // Simple settings dialog for measure mode and user name
  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _userName);
    int tempMode = _measureMode;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                maxLength: 30,
                decoration: const InputDecoration(labelText: 'User Name (max 30)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: tempMode,
                decoration: const InputDecoration(labelText: 'Measure Mode'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('0')),
                  DropdownMenuItem(value: 1, child: Text('1')),
                ],
                onChanged: (v) => tempMode = v ?? 0,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  _userName = nameController.text.trim();
                  _measureMode = tempMode;
                });
                await _saveConfigToStorage();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // _showConfigDialog removed; use _openSettings instead.

  Future<void> _startNfcScan() async {
    setState(() {
      _nfcStatus = 'Scanning... Touch the ST25DV tag to the phone.';
      _eepromData = null;
      _scanning = true;
    });
    bool isAvailable = await nfc.NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _nfcStatus = 'NFC is not available on this device.';
        _scanning = false;
      });
      return;
    }
    nfc.NfcManager.instance.startSession(
      onDiscovered: (nfc.NfcTag tag) async {
        try {
          // Prefer raw ISO15693/NfcV reads to avoid NDEF overhead
          // Read 128 bytes (adjust as needed)
          const int length = 128;
          const int startBlock = 0;
          const int blockSize = 4;

      // iOS raw path can be added here if required

          final vAndroid = android.NfcVAndroid.from(tag);
          if (vAndroid != null) {
            final uid = vAndroid.tag.id; // 8-byte UID
            final data = await _readNfcVAndroid(vAndroid, uid, length: length, startBlock: startBlock, blockSize: blockSize);
            final hex = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
            setState(() {
              _eepromData = hex;
              _nfcStatus = 'EEPROM data read (NFC-V Android raw).';
              _scanning = false;
            });
            await nfc.NfcManager.instance.stopSession();
            return;
          }

          // Fallback to NDEF if raw path not available
          final ndefTag = ndef.Ndef.from(tag);
          if (ndefTag != null) {
            final msg = await ndefTag.read();
            final payloads = msg?.records.map((r) => r.payload).toList() ?? [];
            if (payloads.isEmpty) {
              setState(() {
                _nfcStatus = 'No NDEF message found.';
                _scanning = false;
              });
              await nfc.NfcManager.instance.stopSession();
              return;
            }
            final hexData = payloads.map((b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')).join('\n');
            setState(() {
              _eepromData = hexData;
              _nfcStatus = 'NDEF data read (fallback).';
              _scanning = false;
            });
            await nfc.NfcManager.instance.stopSession();
            return;
          }

          throw Exception('Tag does not support ISO15693/NfcV or NDEF read.');
        } catch (e) {
          setState(() {
            _nfcStatus = 'Error reading tag: $e';
            _scanning = false;
          });
          await nfc.NfcManager.instance.stopSession(errorMessageIos: e.toString());
        }
      },
      pollingOptions: {nfc.NfcPollingOption.iso15693},
    );
  }

  // Persist user config locally
  Future<void> _saveConfigToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _userName);
    await prefs.setInt('measureMode', _measureMode);
  }

  Future<void> _loadConfigFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? '';
      _measureMode = prefs.getInt('measureMode') ?? 0;
    });
  }

  // _buildConfigBytes removed; using explicit memory-map writes instead.

  Future<void> _uploadConfigToNfc() async {
    setState(() {
      _nfcStatus = 'Ready to upload config. Touch the ST25DV tag to the phone.';
      _scanning = true;
    });
  bool isAvailable = await nfc.NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _nfcStatus = 'NFC is not available on this device.';
        _scanning = false;
      });
      return;
    }
    nfc.NfcManager.instance.startSession(
      onDiscovered: (nfc.NfcTag tag) async {
        try {
          // Write per memory map using raw ISO15693
          // Prepare values
          final nameBytes = Uint8List.fromList(utf8.encode(_userName).take(30).toList());
          final nameLen = nameBytes.length;
          List<int> _be32(int v) => [
                (v >> 24) & 0xFF,
                (v >> 16) & 0xFF,
                (v >> 8) & 0xFF,
                v & 0xFF,
              ];

          // Prefer platform ISO15693/NfcV access to avoid NDEF overhead
          // final ios15693 = ios.Iso15693Ios.from(tag);
          // if (ios15693 != null) {
          //   await _writeIso15693Ios(ios15693, data, startBlock: 0, blockSize: 4);
          //   setState(() {
          //     _nfcStatus = 'Config written (ISO15693 iOS raw).';
          //     _scanning = false;
          //   });
          //   await nfc.NfcManager.instance.stopSession();
          //   return;
          // }

          final vAndroid = android.NfcVAndroid.from(tag);
          if (vAndroid != null) {
            final uid = vAndroid.tag.id; // 8-byte UID
            // Write MEASURE_MODE (4 bytes) at offset 16 (block 4)
            await _writeNfcVAndroid(
              vAndroid,
              uid,
              Uint8List.fromList(_be32(_measureMode)),
              startBlock: MEM_VAL_MEASURE_MODE ~/ 4,
              blockSize: 4,
            );
            // Write USER_NAME_LENGTH (4 bytes) at offset 44 (block 11)
            await _writeNfcVAndroid(
              vAndroid,
              uid,
              Uint8List.fromList(_be32(nameLen)),
              startBlock: MEM_VAL_USER_NAME_LENGTH ~/ 4,
              blockSize: 4,
            );
            // Write USER_NAME bytes starting at offset 48 (block 12)
            final paddedLen = ((nameLen + 3) ~/ 4) * 4; // multiple of 4
            final totalBlocks = paddedLen ~/ 4;
            for (int i = 0; i < totalBlocks; i++) {
              final base = i * 4;
              final chunk = Uint8List.fromList([
                base + 0 < nameLen ? nameBytes[base + 0] : 0x00,
                base + 1 < nameLen ? nameBytes[base + 1] : 0x00,
                base + 2 < nameLen ? nameBytes[base + 2] : 0x00,
                base + 3 < nameLen ? nameBytes[base + 3] : 0x00,
              ]);
              await _writeNfcVAndroid(
                vAndroid,
                uid,
                chunk,
                startBlock: (MEM_VAL_USER_NAME ~/ 4) + i,
                blockSize: 4,
              );
            }
            setState(() {
              _nfcStatus = 'Config written (NFC-V Android raw, memory map).';
              _scanning = false;
            });
            await nfc.NfcManager.instance.stopSession();
            return;
          }

          // Fallback: NDEF (if nothing else available)
          final ndefTag = ndef.Ndef.from(tag);
          if (ndefTag != null && ndefTag.isWritable) {
            final payload = Uint8List.fromList([
              ..._be32(_measureMode),
              ..._be32(nameLen),
              ...nameBytes,
            ]);
            final record = ndefrec.NdefRecord(
              typeNameFormat: ndefrec.TypeNameFormat.media,
              type: Uint8List.fromList(ascii.encode('application/octet-stream')),
              identifier: Uint8List(0),
              payload: payload,
            );
            final message = ndefrec.NdefMessage(records: [record]);
            await ndefTag.write(message: message);
            setState(() {
              _nfcStatus = 'Config written via NDEF (fallback).';
              _scanning = false;
            });
            await nfc.NfcManager.instance.stopSession();
            return;
          }

          throw Exception('Tag does not support ISO15693/NfcV or NDEF write.');
        } catch (e) {
          setState(() {
            _nfcStatus = 'Error uploading config: $e';
            _scanning = false;
          });
          await nfc.NfcManager.instance.stopSession(errorMessageIos: e.toString());
        }
      },
      pollingOptions: {nfc.NfcPollingOption.iso15693},
    );
  }

  // Write raw bytes to ISO15693 tag on iOS in consecutive 4-byte blocks starting at startBlock.
  // Future<void> _writeIso15693Ios(
  //   ios.Iso15693Ios tag,
  //   Uint8List data, {
  //   int startBlock = 0,
  //   int blockSize = 4,
  // }) async {
  //   final flags = <ios.Iso15693RequestFlagIos>{
  //     ios.Iso15693RequestFlagIos.highDataRate,
  //     ios.Iso15693RequestFlagIos.address,
  //   };
  //   final totalBlocks = (data.length + blockSize - 1) ~/ blockSize;
  //   for (int i = 0; i < totalBlocks; i++) {
  //     final offset = i * blockSize;
  //     final chunk = Uint8List(blockSize);
  //     for (int j = 0; j < blockSize; j++) {
  //       final src = offset + j;
  //       chunk[j] = src < data.length ? data[src] : 0;
  //     }
  //     await tag.writeSingleBlock(
  //       requestFlags: flags,
  //       blockNumber: startBlock + i,
  //       dataBlock: chunk,
  //     );
  //   }
  // }

  // Write raw bytes to ISO15693 tag on Android using NfcV transceive (addressed mode, 4-byte blocks).
  Future<void> _writeNfcVAndroid(
    android.NfcVAndroid v,
    Uint8List uid,
    Uint8List data, {
    int startBlock = 0,
    int blockSize = 4,
  }) async {
    // ISO15693 Flags: addressed (0x20) + high data rate (0x02)
    const int flags = 0x22;
    const int cmdWriteSingleBlock = 0x21; // ISO15693 Write Single Block

    final totalBlocks = (data.length + blockSize - 1) ~/ blockSize;
    for (int i = 0; i < totalBlocks; i++) {
      final offset = i * blockSize;
      final block = Uint8List(blockSize);
      for (int j = 0; j < blockSize; j++) {
        final k = offset + j;
        block[j] = k < data.length ? data[k] : 0;
      }

      // Frame: FLAGS | CMD | UID(8) | BLOCK# | DATA(blockSize)
      final frame = BytesBuilder();
      frame.add([flags, cmdWriteSingleBlock]);
      frame.add(uid); // Many devices accept id as-is; adjust endianness if required by your tag
      frame.add([startBlock + i]);
      frame.add(block);

      final response = await v.transceive(frame.toBytes());
      // Optional: check response[0] == 0x00 (success) per ISO15693 response format
      if (response.isEmpty || response[0] != 0x00) {
        throw Exception('Write block ${startBlock + i} failed (resp: ${response.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ')})');
      }
    }
  }

  // Read raw bytes from ISO15693 tag on iOS.
  // Future<Uint8List> _readIso15693Ios(
  //   ios.Iso15693Ios tag, {
  //   required int length,
  //   int startBlock = 0,
  //   int blockSize = 4,
  // }) async {
  //   final flags = <ios.Iso15693RequestFlagIos>{
  //     ios.Iso15693RequestFlagIos.highDataRate,
  //     ios.Iso15693RequestFlagIos.address,
  //   };
  //   final blocksToRead = (length + blockSize - 1) ~/ blockSize;
  //   // Try multi-block read for efficiency
  //   final blocks = await tag.readMultipleBlocks(
  //     requestFlags: flags,
  //     blockNumber: startBlock,
  //     numberOfBlocks: blocksToRead,
  //   );
  //   final buf = BytesBuilder();
  //   for (final b in blocks) {
  //     buf.add(b);
  //   }
  //   final bytes = buf.toBytes();
  //   return Uint8List.fromList(bytes.take(length).toList());
  // }

  // Read raw bytes from ISO15693 tag on Android using NfcV transceive.
  Future<Uint8List> _readNfcVAndroid(
    android.NfcVAndroid v,
    Uint8List uid, {
    required int length,
    int startBlock = 0,
    int blockSize = 4,
  }) async {
    // Flags: addressed + high data rate
    const int flags = 0x22;
    const int cmdReadSingleBlock = 0x20; // ISO15693 Read Single Block
    final blocksToRead = (length + blockSize - 1) ~/ blockSize;
    final out = BytesBuilder();
    for (int i = 0; i < blocksToRead; i++) {
      final frame = BytesBuilder();
      frame.add([flags, cmdReadSingleBlock]);
      frame.add(uid);
      frame.add([startBlock + i]);
      final resp = await v.transceive(frame.toBytes());
      if (resp.isEmpty || resp[0] != 0x00) {
        throw Exception('Read block ${startBlock + i} failed (resp: ${resp.map((b)=>b.toRadixString(16).padLeft(2,'0')).join(' ')})');
      }
      // Skip status byte (0x00) and append block data
      out.add(resp.sublist(1));
    }
    final bytes = out.toBytes();
    return Uint8List.fromList(bytes.take(length).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Config',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show config summary if set
            if (_userName.isNotEmpty)
              Column(
                children: [
                  if (_userName.isNotEmpty)
                    Text('User Name: $_userName', textAlign: TextAlign.center),
                  Text('Measure Mode: $_measureMode', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                ],
              ),
            Text(_nfcStatus, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_eepromData != null) ...[
              const Text('EEPROM Data (hex):', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(_eepromData!, style: const TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 24),
            ],
            ElevatedButton.icon(
              onPressed: _scanning ? null : _startNfcScan,
              icon: const Icon(Icons.nfc),
              label: const Text('Start NFC Scan'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _uploadConfigToNfc,
              icon: const Icon(Icons.upload),
              label: const Text('Upload Config to NFC'),
            ),
          ],
        ),
      ),
    );
  }
}
