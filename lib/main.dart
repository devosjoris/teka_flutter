import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart' as nfc;
import 'package:nfc_manager/nfc_manager_android.dart' as android;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

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

// Log entry from sensor (matches NfcDtLogEntry in nfc_data_transfer.h)
class SensorLogEntry {
  final int sensorValue;
  final int unixTimestamp;
  final bool rtcValid;
  final bool readoutDone;

  SensorLogEntry({
    required this.sensorValue,
    required this.unixTimestamp,
    required this.rtcValid,
    required this.readoutDone,
  });

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000);

  // JSON serialization for persistence
  Map<String, dynamic> toJson() => {
    'sensorValue': sensorValue,
    'unixTimestamp': unixTimestamp,
    'rtcValid': rtcValid,
    'readoutDone': readoutDone,
  };

  factory SensorLogEntry.fromJson(Map<String, dynamic> json) => SensorLogEntry(
    sensorValue: json['sensorValue'] as int,
    unixTimestamp: json['unixTimestamp'] as int,
    rtcValid: json['rtcValid'] as bool,
    readoutDone: json['readoutDone'] as bool,
  );

  @override
  String toString() {
    return 'SensorLogEntry(value: $sensorValue, time: $dateTime, rtcValid: $rtcValid)';
  }
}

// Show Data Page - displays a chart of sensor data over time
class ShowDataPage extends StatelessWidget {
  final Map<int, SensorLogEntry> sensorData;

  const ShowDataPage({super.key, required this.sensorData});

  @override
  Widget build(BuildContext context) {
    // Sort entries by timestamp
    final sortedEntries = sensorData.values.toList()
      ..sort((a, b) => a.unixTimestamp.compareTo(b.unixTimestamp));

    if (sortedEntries.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sensor Data'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: Text('No sensor data available.\nRead sensor values first.'),
        ),
      );
    }

    // Create chart data points
    final spots = sortedEntries.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.sensorValue.toDouble());
    }).toList();

    // Calculate min/max for Y axis
    final minValue = sortedEntries.map((e) => e.sensorValue).reduce((a, b) => a < b ? a : b);
    final maxValue = sortedEntries.map((e) => e.sensorValue).reduce((a, b) => a > b ? a : b);
    final yMin = (minValue * 0.9).floorToDouble();
    final yMax = (maxValue * 1.1).ceilToDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text('Sensor Data (${sortedEntries.length} points)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Time range info
            Text(
              'From: ${sortedEntries.first.dateTime.toLocal()}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'To: ${sortedEntries.last.dateTime.toLocal()}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            // Chart
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: (yMax - yMin) / 5,
                    verticalInterval: sortedEntries.length > 10 ? sortedEntries.length / 5 : 1,
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: const Text('Time'),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: sortedEntries.length > 10 ? sortedEntries.length / 5 : 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= sortedEntries.length) {
                            return const SizedBox.shrink();
                          }
                          final entry = sortedEntries[index];
                          final dt = entry.dateTime.toLocal();
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Transform.rotate(
                              angle: -0.5,
                              child: Text(
                                '${dt.month}/${dt.day}\n${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: const Text('µg/m³'),
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: (yMax - yMin) / 5,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey),
                  ),
                  minX: 0,
                  maxX: (sortedEntries.length - 1).toDouble(),
                  minY: yMin,
                  maxY: yMax,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: sortedEntries.length <= 50,
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.x.toInt();
                          if (index < 0 || index >= sortedEntries.length) {
                            return null;
                          }
                          final entry = sortedEntries[index];
                          return LineTooltipItem(
                            '${entry.sensorValue} µg/m³\n${entry.dateTime.toLocal()}',
                            const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Data list
            Expanded(
              child: ListView.builder(
                itemCount: sortedEntries.length,
                itemBuilder: (context, index) {
                  final entry = sortedEntries[sortedEntries.length - 1 - index]; // Newest first
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${entry.sensorValue} µg/m³',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${entry.dateTime.toLocal()}${entry.rtcValid ? '' : ' (RTC invalid)'}',
                    ),
                    leading: Text(
                      '${sortedEntries.length - index}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  String _nfcStatus = 'Tap "Start NFC Scan" and touch the ST25DV tag.';
  String? _eepromData;
  bool _scanning = false;
  String? _progressDetail; // shows current read/write step
  // Memory map (byte offsets)
  static const int MEM_VAL_TIMESTAMP = 4; // 4 bytes (block 4)
  static const int MEM_VAL_NEWTIMESTAMP = 36; // 4 bytes (block 7)
  // static const int MEM_PTR_TIMESTAMP = 0; // not used at the moment

  static const int MEM_VAL_MEASURE_MODE = 16; // 4 bytes (block 4)
  static const int MEM_VAL_USER_NAME_LENGTH = 44; // 4 bytes (block 11)
  static const int MEM_VAL_USER_NAME = 48; // 30 bytes (blocks 12..19)
  static const int MEM_VAL_WARNING_LEVEL = 80; // 4 bytes (block 20)
  static const int MEM_VAL_MAX_LEVEL = 84; // 4 bytes (block 21)
  static const int MEM_PTR_LAST_WRITE = 8; // 4 bytes (block 2)
  static const int MEM_VAL_DATA_START = 200;
  static const int MEM_VAL_DATA_END = 8188;

  // Data Transfer Protocol addresses (from nfc_data_transfer.h)
  static const int NFC_DT_CMD_ADDR = 0x60; // 96 - Command field
  static const int NFC_DT_STATUS_ADDR = 0x64; // 100 - Status field
  static const int NFC_DT_FIELD_COUNT_ADDR =
      0x68; // 104 - Number of entries in batch
  static const int NFC_DT_TOTAL_PENDING_ADDR =
      0x6C; // 108 - Total entries pending
  static const int NFC_DT_CRC32_ADDR = 0x70; // 112 - CRC32 of data
  static const int NFC_DT_DATA_LEN_ADDR = 0x74; // 116 - Length of data payload
  static const int NFC_DT_DATA_START_ADDR = 0xC8; // 200 - Start of data payload
  static const int NFC_DT_ENTRY_SIZE = 12; // Each log entry is 12 bytes

  // Commands from app (written to CMD_FIELD)
  static const int NFC_DT_CMD_NONE = 0x00000000; // No command / idle
  static const int NFC_DT_CMD_REQUEST_DATA =
      0x52455144; // 'DREQ' - Request sensor data
  static const int NFC_DT_CMD_ACK_DATA =
      0x41434B44; // 'DACK' - Acknowledge data received
  static const int NFC_DT_CMD_NACK_DATA =
      0x4E41434B; // 'NACK' - CRC mismatch, resend
  static const int NFC_DT_CMD_RESET_FLAGS =
      0x52535446; // 'RSTF' - Clear all READOUT_DONE flags

  // Status from ESP32 (written to STATUS_FIELD)
  static const int NFC_DT_STATUS_IDLE = 0x00000000; // Idle
  static const int NFC_DT_STATUS_DATA_READY = 0x44524459; // 'DRDY' - Data ready
  static const int NFC_DT_STATUS_ACK_OK = 0x41434F4B; // 'ACOK' - ACK processed
  static const int NFC_DT_STATUS_NO_DATA = 0x4E444154; // 'NDAT' - No new data
  static const int NFC_DT_STATUS_ERROR = 0x45525221; // 'ERR!' - Error
  static const int NFC_DT_STATUS_BUSY = 0x42555359; // 'BUSY' - Processing

  // Sensor log entries read from device
  List<SensorLogEntry> _sensorLogEntries = [];

  // Stored sensor data - dictionary with timestamp as key to avoid duplicates
  final Map<int, SensorLogEntry> _sensorDataStore = {};

  // Config fields
  String _userName = '';
  int _measureMode = 0; // 0 or 1
  int _warningLevel = 0; // ug/m3
  int _maxLevel = 0; // ug/m3
  int? _lastWriteAddress; // discovered address of magic marker
  Timer? _disconnectTimer; // grace timer to re-enable connect after disconnect
  int? _lastTimestampWriteMs; // last time app wrote a timestamp to the device

  // Little-endian helpers (EEPROM stores values little-endian)
  List<int> _le32(int v) => [
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ];
  int _u32le(Uint8List b, [int off = 0]) =>
      (b[off] & 0xFF) |
      ((b[off + 1] & 0xFF) << 8) |
      ((b[off + 2] & 0xFF) << 16) |
      ((b[off + 3] & 0xFF) << 24);

  // CRC32 calculation (standard polynomial 0xEDB88320, matches ESP32 implementation)
  static final List<int> _crc32Table = _generateCrc32Table();
  static List<int> _generateCrc32Table() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int byte in data) {
      crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  // Parse log entries from raw data
  List<SensorLogEntry> _parseLogEntries(Uint8List data, int count) {
    final entries = <SensorLogEntry>[];
    for (int i = 0; i < count; i++) {
      final offset = i * NFC_DT_ENTRY_SIZE;
      if (offset + NFC_DT_ENTRY_SIZE > data.length) break;
      final sensorValue = _u32le(data, offset);
      final unixTimestamp = _u32le(data, offset + 4);
      final flags = data[offset + 8];
      entries.add(
        SensorLogEntry(
          sensorValue: sensorValue,
          unixTimestamp: unixTimestamp,
          rtcValid: (flags & 0x01) != 0,
          readoutDone: (flags & 0x02) != 0,
        ),
      );
    }
    return entries;
  }

  @override
  void initState() {
    super.initState();
    _loadConfigFromStorage();
  }

  // Simple settings dialog for measure mode and user name
  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _userName);
    final warningController = TextEditingController(
      text: _warningLevel.toString(),
    );
    final maxController = TextEditingController(text: _maxLevel.toString());
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
                decoration: const InputDecoration(
                  labelText: 'User Name (max 30)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: tempMode,
                decoration: const InputDecoration(labelText: 'Measure Mode'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('1 minute refresh')),
                  DropdownMenuItem(value: 1, child: Text('5 minutes refresh')),
                ],
                onChanged: (v) => tempMode = v ?? 0,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: warningController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Warning level (ug/m³, < 5000)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max level (ug/m³, < 7000)',
                ),
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
                // Parse and validate
                final name = nameController.text.trim();
                final warn = int.tryParse(warningController.text.trim()) ?? -1;
                final maxv = int.tryParse(maxController.text.trim()) ?? -1;
                if (maxv <= 0 || maxv > 7000) {
                  await showDialog(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Invalid Max level'),
                      content: Text(
                        'Max level must be a positive integer below 7000.',
                      ),
                    ),
                  );
                  return;
                }
                if (warn < 0 || warn > 5000) {
                  await showDialog(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Invalid Warning level'),
                      content: Text(
                        'Warning level must be a non-negative integer below 5000.',
                      ),
                    ),
                  );
                  return;
                }
                if (warn >= maxv) {
                  await showDialog(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Invalid levels'),
                      content: Text(
                        'Warning level must be less than Max level.',
                      ),
                    ),
                  );
                  return;
                }
                setState(() {
                  _userName = name;
                  _measureMode = tempMode;
                  _warningLevel = warn;
                  _maxLevel = maxv;
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

  Future<void> _connectToSensor() async {
    setState(() {
      _nfcStatus = 'Connecting... Touch the ST25DV tag to the phone.';
      _eepromData = null;
      _scanning = true;
      _progressDetail = 'Waiting for tag...';
    });
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    final isAvailable = await nfc.NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _nfcStatus = 'NFC is not available on this device.';
        _scanning = false;
      });
      return;
    }
    nfc.NfcManager.instance.startSession(
      pollingOptions: {nfc.NfcPollingOption.iso15693},
      onDiscovered: (nfc.NfcTag tag) async {
        try {
          final vAndroid = android.NfcVAndroid.from(tag);
          if (vAndroid == null) {
            throw Exception(
              'ISO15693 (NFC-V) not available; cannot read raw memory.',
            );
          }
          final uid = vAndroid.tag.id;

          // Helper to check if error is a temporary NFC disconnect
          bool isTemporaryDisconnect(dynamic e) {
            final errorStr = e.toString().toLowerCase();
            return errorStr.contains('taglost') ||
                errorStr.contains('tag lost') ||
                errorStr.contains('transceive') ||
                errorStr.contains('io exception') ||
                errorStr.contains('ioexception');
          }

          // Local helper: read from NFC with retry for temporary disconnects
          Future<Uint8List> readNFC(int length, int address) async {
            const maxRetries = 500;
            const retryDelayMs = 100;
            for (int attempt = 0; attempt < maxRetries; attempt++) {
              try {
                return await _readNfcVAndroid(
                  vAndroid,
                  uid,
                  length: length,
                  startBlock: address ~/ 4,
                );
              } catch (e) {
                if (isTemporaryDisconnect(e) && attempt < maxRetries - 1) {
                  print('[NFC] Read failed (attempt ${attempt + 1}/$maxRetries), retrying in ${retryDelayMs}ms...');
                  setState(() {
                    _progressDetail = 'NFC reconnecting... (${attempt + 1}/$maxRetries)';
                  });
                  await Future.delayed(Duration(milliseconds: retryDelayMs));
                  continue;
                }
                rethrow;
              }
            }
            throw Exception('Read failed after $maxRetries attempts');
          }

          // Local helper: write to NFC with retry for temporary disconnects
          Future<void> writeNFC(Uint8List data, int address) async {
            const maxRetries = 500;
            const retryDelayMs = 100;
            for (int attempt = 0; attempt < maxRetries; attempt++) {
              try {
                await _writeNfcVAndroid(
                  vAndroid,
                  uid,
                  data,
                  startBlock: address ~/ 4,
                );
                return;
              } catch (e) {
                if (isTemporaryDisconnect(e) && attempt < maxRetries - 1) {
                  print('[NFC] Write failed (attempt ${attempt + 1}/$maxRetries), retrying in ${retryDelayMs}ms...');
                  setState(() {
                    _progressDetail = 'NFC reconnecting... (${attempt + 1}/$maxRetries)';
                  });
                  await Future.delayed(Duration(milliseconds: retryDelayMs));
                  continue;
                }
                rethrow;
              }
            }
            throw Exception('Write failed after $maxRetries attempts');
          }

          // Write timestamp to NFC
          await _updateNFCTimestamp(writeNFC);

          // 1) Read current values from sensor
          setState(() {
            _progressDetail =
                'Reading measure mode @ 0x${MEM_VAL_MEASURE_MODE.toRadixString(16)}';
          });
          final mmBytes = await readNFC(4, MEM_VAL_MEASURE_MODE);
          final mmTag = _u32le(mmBytes);

          setState(() {
            _progressDetail =
                'Reading name length @ 0x${MEM_VAL_USER_NAME_LENGTH.toRadixString(16)}';
          });
          final nameLenBytes = await readNFC(4, MEM_VAL_USER_NAME_LENGTH);
          int nameLenTag = _u32le(nameLenBytes);
          if (nameLenTag < 0) nameLenTag = 0;
          if (nameLenTag > 30) nameLenTag = 30;
          final paddedNameLen = ((nameLenTag + 3) ~/ 4) * 4;
          String nameTag = '';
          if (nameLenTag > 0) {
            setState(() {
              _progressDetail =
                  'Reading name bytes (${nameLenTag}B) starting @ 0x${MEM_VAL_USER_NAME.toRadixString(16)}';
            });
            final nameBytes = await readNFC(paddedNameLen, MEM_VAL_USER_NAME);
            nameTag = utf8.decode(
              nameBytes.sublist(0, nameLenTag),
              allowMalformed: true,
            );
          }

          setState(() {
            _progressDetail =
                'Reading warning level @ 0x${MEM_VAL_WARNING_LEVEL.toRadixString(16)}';
          });
          final warnBytes = await readNFC(4, MEM_VAL_WARNING_LEVEL);
          final warnTag = _u32le(warnBytes);

          setState(() {
            _progressDetail =
                'Reading max level @ 0x${MEM_VAL_MAX_LEVEL.toRadixString(16)}';
          });
          final maxBytes = await readNFC(4, MEM_VAL_MAX_LEVEL);
          final maxTag = _u32le(maxBytes);

          // Compare with app values
          final diffs = <String>[];
          if (mmTag != _measureMode)
            diffs.add('Measure Mode: sensor=$mmTag, app=$_measureMode');
          if (nameTag != _userName)
            diffs.add('User Name: sensor="$nameTag", app="$_userName"');
          if (warnTag != _warningLevel)
            diffs.add('Warning Level: sensor=$warnTag, app=$_warningLevel');
          if (maxTag != _maxLevel)
            diffs.add('Max Level: sensor=$maxTag, app=$_maxLevel');

          bool doUpdate = false;
          if (diffs.isNotEmpty) {
            doUpdate =
                await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Update sensor values?'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Differences detected:'),
                        const SizedBox(height: 8),
                        ...diffs.map((d) => Text('• $d')),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                ) ??
                false;
          }

          if (doUpdate) {
            // Perform writes (same as upload path)
            final nameBytesApp = Uint8List.fromList(
              utf8.encode(_userName).take(30).toList(),
            );
            final nameLenApp = nameBytesApp.length;

            // Write measure mode
            setState(() {
              _progressDetail =
                  'Writing measure mode @ 0x${MEM_VAL_MEASURE_MODE.toRadixString(16)}';
            });
            await writeNFC(
              Uint8List.fromList(_le32(_measureMode)),
              MEM_VAL_MEASURE_MODE,
            );
            // Write name length
            setState(() {
              _progressDetail =
                  'Writing name length @ 0x${MEM_VAL_USER_NAME_LENGTH.toRadixString(16)}';
            });
            await writeNFC(
              Uint8List.fromList(_le32(nameLenApp)),
              MEM_VAL_USER_NAME_LENGTH,
            );
            // Write name bytes
            final paddedLenApp = ((nameLenApp + 3) ~/ 4) * 4;
            final totalBlocks = paddedLenApp ~/ 4;
            for (int i = 0; i < totalBlocks; i++) {
              final base = i * 4;
              final addr = MEM_VAL_USER_NAME + base;
              setState(() {
                _progressDetail =
                    'Writing name block @ 0x${addr.toRadixString(16)}';
              });
              final chunk = Uint8List.fromList([
                base + 0 < nameLenApp ? nameBytesApp[base + 0] : 0x00,
                base + 1 < nameLenApp ? nameBytesApp[base + 1] : 0x00,
                base + 2 < nameLenApp ? nameBytesApp[base + 2] : 0x00,
                base + 3 < nameLenApp ? nameBytesApp[base + 3] : 0x00,
              ]);
              await writeNFC(chunk, addr);
            }
            // Write warning and max levels
            setState(() {
              _progressDetail =
                  'Writing warning level @ 0x${MEM_VAL_WARNING_LEVEL.toRadixString(16)}';
            });
            await writeNFC(
              Uint8List.fromList(_le32(_warningLevel)),
              MEM_VAL_WARNING_LEVEL,
            );
            setState(() {
              _progressDetail =
                  'Writing max level @ 0x${MEM_VAL_MAX_LEVEL.toRadixString(16)}';
            });
            await writeNFC(
              Uint8List.fromList(_le32(_maxLevel)),
              MEM_VAL_MAX_LEVEL,
            );
          }

          // 2) Read last_write_guess and scan for magic 0xC1EAC1EA in ring buffer region
          const int magic = 0xC1EAC1EA;
          setState(() {
            _progressDetail =
                'Reading last_write_guess @ 0x${MEM_PTR_LAST_WRITE.toRadixString(16)}';
          });
          final guessBytes = await readNFC(4, MEM_PTR_LAST_WRITE);
          int guess = _u32le(guessBytes);
          // Clamp guess into ring region and align to 4
          if (guess < MEM_VAL_DATA_START) guess = MEM_VAL_DATA_START;
          if (guess > MEM_VAL_DATA_END) guess = MEM_VAL_DATA_START;
          guess = (guess ~/ 4) * 4;
          // Iterate over the ring once max
          final int ringSpan =
              MEM_VAL_DATA_END -
              MEM_VAL_DATA_START +
              4; // inclusive end, 4-byte step
          final int maxIters = (ringSpan ~/ 4);
          int? foundAddress;
          int addr = guess;
          for (int i = 0; i < maxIters; i++) {
            setState(() {
              _progressDetail = 'Scanning marker @ ${addr}';
            });
            final valBytes = await readNFC(4, addr);
            final val = _u32le(valBytes);
            // Verbose terminal logging for scan loop: address and decoded value (hex)
            print(
              "[NFC] scan addr=0x${addr.toRadixString(16)} val=0x${val.toRadixString(16).padLeft(8, '0')}",
            );
            if (val == magic) {
              foundAddress = addr;
              break;
            }
            // advance with wrap in ring
            addr += 4;
            if (addr > MEM_VAL_DATA_END) addr = MEM_VAL_DATA_START;
          }

          // If marker found, write timestamp to that address and rewrite magic at address+4
          if (foundAddress != null) {}

          setState(() {
            _lastWriteAddress = foundAddress;
            _nfcStatus = foundAddress != null
                ? 'Connected. Last write marker at byte $foundAddress.'
                : 'Connected. Last write marker not found.';
            _scanning = false;
            _progressDetail = null;
          });
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
          await nfc.NfcManager.instance.stopSession();
        } catch (e) {
          // Check if this is a connection dropped error
          final errorStr = e.toString().toLowerCase();
          final isConnectionDropped = errorStr.contains('taglost') ||
              errorStr.contains('tag lost') ||
              errorStr.contains('transceive') ||
              errorStr.contains('io exception') ||
              errorStr.contains('ioexception') ||
              errorStr.contains('connection') ||
              errorStr.contains('removed');

          setState(() {
            if (isConnectionDropped) {
              _nfcStatus = 'NFC connection dropped. Please try again.';
            } else {
              _nfcStatus = 'NFC error: $e';
            }
            // Keep _scanning true during grace period to prevent duplicate taps
          });
          _disconnectTimer?.cancel();
          _disconnectTimer = Timer(const Duration(seconds: 3), () async {
            if (!mounted) return;
            setState(() {
              _scanning = false; // re-enable button
              _progressDetail = null;
              if (isConnectionDropped) {
                _nfcStatus = 'Connection lost. You can connect again.';
              } else {
                _nfcStatus = 'NFC disconnected. You can connect again.';
              }
            });
            try {
              await nfc.NfcManager.instance.stopSession();
            } catch (_) {}
          });
        }
      },
    );
  }

  // _startNfcScan removed; merged into _connectToSensor

  // Allow user to stop scanning/session manually
  Future<void> _stopScanning() async {
    // Immediately update UI
    setState(() {
      _scanning = false;
      _progressDetail = null;
      _nfcStatus = 'Scanning stopped.';
    });
    // Cancel any grace timer
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    // Attempt to stop the NFC session (ignore errors if session already closed)
    try {
      await nfc.NfcManager.instance.stopSession();
    } catch (_) {}
  }

  // Persist user config locally
  Future<void> _saveConfigToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _userName);
    await prefs.setInt('measureMode', _measureMode);
    await prefs.setInt('warningLevel', _warningLevel);
    await prefs.setInt('maxLevel', _maxLevel);
  }

  Future<void> _loadConfigFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? '';
      _measureMode = prefs.getInt('measureMode') ?? 0;
      _warningLevel = prefs.getInt('warningLevel') ?? 0;
      _maxLevel = prefs.getInt('maxLevel') ?? 0;
      _lastTimestampWriteMs = prefs.getInt('lastTsWriteMs');
    });
    // Load sensor data from storage
    await _loadSensorDataFromStorage();
  }

  // Save sensor data to persistent storage
  Future<void> _saveSensorDataToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList = _sensorDataStore.values
        .map((entry) => jsonEncode(entry.toJson()))
        .toList();
    await prefs.setStringList('sensorData', jsonList);
  }

  // Load sensor data from persistent storage
  Future<void> _loadSensorDataFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonList = prefs.getStringList('sensorData');
    if (jsonList != null) {
      setState(() {
        _sensorDataStore.clear();
        for (final jsonStr in jsonList) {
          try {
            final entry = SensorLogEntry.fromJson(jsonDecode(jsonStr));
            _sensorDataStore[entry.unixTimestamp] = entry;
          } catch (e) {
            print('[Storage] Failed to parse sensor entry: $e');
          }
        }
      });
      print('[Storage] Loaded ${_sensorDataStore.length} sensor entries from storage');
    }
  }

  Future<void> _setLastTimestampWriteMs(int ms) async {
    setState(() {
      _lastTimestampWriteMs = ms;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastTsWriteMs', ms);
  }

  // Write current UNIX timestamp and NEWTIMESTAMP marker to NFC
  Future<void> _updateNFCTimestamp(Future<void> Function(Uint8List data, int address) writeNFC) async {
    // Write current UNIX time (seconds, force LSB=1) to MEM_VAL_TIMESTAMP
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int nowSec = (nowMs ~/ 1000) | 1;
    setState(() {
      _progressDetail =
          'Writing timestamp @ 0x${MEM_VAL_TIMESTAMP.toRadixString(16)} = $nowSec';
    });
    await writeNFC(Uint8List.fromList(_le32(nowSec)), MEM_VAL_TIMESTAMP);
    await _setLastTimestampWriteMs(nowMs);

    // Write fixed value 0x0000501D to MEM_VAL_NEWTIMESTAMP (little-endian)
    setState(() {
      _progressDetail =
          'Writing NEWTIMESTAMP @ 0x${MEM_VAL_NEWTIMESTAMP.toRadixString(16)} = 0x0000501D';
    });
    await writeNFC(
      Uint8List.fromList(_le32(20509)),
      MEM_VAL_NEWTIMESTAMP,
    ); // 0x501D
  }

  // Read sensor values using the NFC Data Transfer Protocol
  Future<void> _readSensorValues() async {
    setState(() {
      _nfcStatus =
          'Reading sensor values... Touch the ST25DV tag to the phone.';
      _eepromData = null;
      _scanning = true;
      _progressDetail = 'Waiting for tag...';
      _sensorLogEntries = [];
    });
    _disconnectTimer?.cancel();
    _disconnectTimer = null;

    final isAvailable = await nfc.NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _nfcStatus = 'NFC is not available on this device.';
        _scanning = false;
      });
      return;
    }

    nfc.NfcManager.instance.startSession(
      pollingOptions: {nfc.NfcPollingOption.iso15693},
      onDiscovered: (nfc.NfcTag tag) async {
        try {
          final vAndroid = android.NfcVAndroid.from(tag);
          if (vAndroid == null) {
            throw Exception(
              'ISO15693 (NFC-V) not available; cannot read raw memory.',
            );
          }
          final uid = vAndroid.tag.id;

          // Helper to check if error is a temporary NFC disconnect
          bool isTemporaryDisconnect(dynamic e) {
            final errorStr = e.toString().toLowerCase();
            return errorStr.contains('taglost') ||
                errorStr.contains('tag lost') ||
                errorStr.contains('transceive') ||
                errorStr.contains('io exception') ||
                errorStr.contains('ioexception');
          }

          // Local helper: read from NFC with retry for temporary disconnects
          Future<Uint8List> readNFC(int length, int address) async {
            const maxRetries = 500;
            const retryDelayMs = 100;
            for (int attempt = 0; attempt < maxRetries; attempt++) {
              try {
                return await _readNfcVAndroid(
                  vAndroid,
                  uid,
                  length: length,
                  startBlock: address ~/ 4,
                );
              } catch (e) {
                if (isTemporaryDisconnect(e) && attempt < maxRetries - 1) {
                  print('[NFC] Read failed (attempt ${attempt + 1}/$maxRetries), retrying in ${retryDelayMs}ms...');
                  setState(() {
                    _progressDetail = 'NFC reconnecting... (${attempt + 1}/$maxRetries)';
                  });
                  await Future.delayed(Duration(milliseconds: retryDelayMs));
                  continue;
                }
                rethrow;
              }
            }
            throw Exception('Read failed after $maxRetries attempts');
          }

          // Local helper: write to NFC with retry for temporary disconnects
          Future<void> writeNFC(Uint8List data, int address) async {
            const maxRetries = 500;
            const retryDelayMs = 100;
            for (int attempt = 0; attempt < maxRetries; attempt++) {
              try {
                await _writeNfcVAndroid(
                  vAndroid,
                  uid,
                  data,
                  startBlock: address ~/ 4,
                );
                return;
              } catch (e) {
                if (isTemporaryDisconnect(e) && attempt < maxRetries - 1) {
                  print('[NFC] Write failed (attempt ${attempt + 1}/$maxRetries), retrying in ${retryDelayMs}ms...');
                  setState(() {
                    _progressDetail = 'NFC reconnecting... (${attempt + 1}/$maxRetries)';
                  });
                  await Future.delayed(Duration(milliseconds: retryDelayMs));
                  continue;
                }
                rethrow;
              }
            }
            throw Exception('Write failed after $maxRetries attempts');
          }

          final allEntries = <SensorLogEntry>[];
          int totalPending = 0;
          int batchNumber = 0;

          // Loop to read all batches
          while (true) {
            batchNumber++;
            setState(() {
              _progressDetail = 'Batch $batchNumber: Sending data request...';
            });
            print('[NFC DT] $_progressDetail');

            // Write timestamp to NFC
            await _updateNFCTimestamp(writeNFC);

            // Step 1: Write REQUEST_DATA command
            await writeNFC(
              Uint8List.fromList(_le32(NFC_DT_CMD_REQUEST_DATA)),
              NFC_DT_CMD_ADDR,
            );

            // Step 2: Poll for status (with timeout)
            int status = 0;
            const maxPolls = 20000; // 5 seconds max (100ms * 50)
            for (int poll = 0; poll < maxPolls; poll++) {
              await Future.delayed(const Duration(milliseconds: 100));
              setState(() {
                _progressDetail =
                    'Batch $batchNumber: Waiting for ESP32 response (${poll + 1}/$maxPolls)...';
              });
              if (poll % 10 == 0) print('[NFC DT] $_progressDetail');
              final statusBytes = await readNFC(4, NFC_DT_STATUS_ADDR);
              status = _u32le(statusBytes);
              print(
                '[NFC DT] Poll $poll: status=0x${status.toRadixString(16).padLeft(8, '0')}',
              );

              if (status == NFC_DT_STATUS_DATA_READY ||
                  status == NFC_DT_STATUS_NO_DATA ||
                  status == NFC_DT_STATUS_ERROR) {
                break;
              }
            }

            // Check status
            if (status == NFC_DT_STATUS_NO_DATA) {
              setState(() {
                _progressDetail = 'No more data available.';
              });
              print('[NFC DT] $_progressDetail');
              break;
            }
            if (status == NFC_DT_STATUS_ERROR) {
              throw Exception('ESP32 reported an error during data transfer.');
            }
            if (status != NFC_DT_STATUS_DATA_READY) {
              throw Exception(
                'Timeout waiting for data. Status: 0x${status.toRadixString(16)}',
              );
            }

            if (status == NFC_DT_STATUS_DATA_READY) {
              print("DATA READY received from ESP32.");
              setState(() {
                _progressDetail = 'DATA READY received.';
              });
              print('[NFC DT] $_progressDetail');
            }

            // Step 3: Read metadata
            setState(() {
              _progressDetail = 'Batch $batchNumber: Reading metadata...';
            });
            print('[NFC DT] $_progressDetail');
            final countBytes = await readNFC(4, NFC_DT_FIELD_COUNT_ADDR);
            final entryCount = _u32le(countBytes);

            final pendingBytes = await readNFC(4, NFC_DT_TOTAL_PENDING_ADDR);
            totalPending = _u32le(pendingBytes);

            final crcBytes = await readNFC(4, NFC_DT_CRC32_ADDR);
            final expectedCrc = _u32le(crcBytes);

            final lenBytes = await readNFC(4, NFC_DT_DATA_LEN_ADDR);
            final dataLength = _u32le(lenBytes);

            print(
              '[NFC DT] entryCount=$entryCount, totalPending=$totalPending, dataLength=$dataLength, expectedCrc=0x${expectedCrc.toRadixString(16)}',
            );

            if (entryCount == 0 || dataLength == 0) {
              // No data in this batch
              break;
            }

            // Step 4: Read data payload
            setState(() {
              _progressDetail =
                  'Batch $batchNumber: Reading $entryCount entries ($dataLength bytes)...';
            });
            print('[NFC DT] $_progressDetail');
            final dataPayload = await readNFC(
              dataLength,
              NFC_DT_DATA_START_ADDR,
            );

            // Log raw bytes (24 bytes per line = 2 entries)
            print('[NFC DT] Raw data payload ($dataLength bytes):');
            for (int i = 0; i < dataPayload.length; i += 24) {
              final end = (i + 24 < dataPayload.length) ? i + 24 : dataPayload.length;
              final chunk = dataPayload.sublist(i, end);
              final hexLine = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
              print('[NFC DT]   ${i.toString().padLeft(4, '0')}: $hexLine');
            }

            // Step 5: Verify CRC32
            final calculatedCrc = _crc32(dataPayload);
            print(
              '[NFC DT] calculatedCrc=0x${calculatedCrc.toRadixString(16)}',
            );

            if (calculatedCrc != expectedCrc) {
              // CRC mismatch - send NACK and retry this batch
              setState(() {
                _progressDetail =
                    'Batch $batchNumber: CRC mismatch, requesting resend...';
              });
              print('[NFC DT] $_progressDetail');
              await writeNFC(
                Uint8List.fromList(_le32(NFC_DT_CMD_NACK_DATA)),
                NFC_DT_CMD_ADDR,
              );
              continue; // Retry this batch
            }

            // Step 6: Parse entries
            final batchEntries = _parseLogEntries(dataPayload, entryCount);
            allEntries.addAll(batchEntries);
            print(
              '[NFC DT] Parsed ${batchEntries.length} entries from batch $batchNumber',
            );
            // Print each entry in the batch
            for (int i = 0; i < batchEntries.length; i++) {
              final e = batchEntries[i];
              print(
                '[NFC DT]   Entry ${i + 1}: value=${e.sensorValue} µg/m³, time=${e.dateTime.toLocal()}, rtcValid=${e.rtcValid}',
              );
            }

            // Store batch entries immediately (CRC was OK)
            int batchNewCount = 0;
            for (final entry in batchEntries) {
              if (!_sensorDataStore.containsKey(entry.unixTimestamp)) {
                _sensorDataStore[entry.unixTimestamp] = entry;
                batchNewCount++;
              }
            }
            if (batchNewCount > 0) {
              await _saveSensorDataToStorage();
              print('[NFC DT] Saved $batchNewCount new entries from batch $batchNumber to storage');
            }

            // Step 7: Send ACK
            setState(() {
              _progressDetail = 'Batch $batchNumber: Sending acknowledgment...';
            });
            print('[NFC DT] $_progressDetail');
            await writeNFC(
              Uint8List.fromList(_le32(NFC_DT_CMD_ACK_DATA)),
              NFC_DT_CMD_ADDR,
            );

            // Wait briefly for ESP32 to process ACK
            await Future.delayed(const Duration(milliseconds: 2000));

            // Check if more data pending
            if (totalPending <= entryCount) {
              // All data read
              break;
            }
          }

          // Clear command field
          await writeNFC(
            Uint8List.fromList(_le32(NFC_DT_CMD_NONE)),
            NFC_DT_CMD_ADDR,
          );

          // Count how many new entries were added (already stored per-batch)
          int newEntriesCount = 0;
          for (final entry in allEntries) {
            // Check if this entry was new (it's already in store, but we count it)
            // Since we stored per-batch, just count entries that are in the store with matching timestamp
            if (_sensorDataStore.containsKey(entry.unixTimestamp)) {
              newEntriesCount++;
            }
          }
          // Actually we want to count truly new entries - need to track differently
          // Since entries are already stored per-batch, just report totals
          final totalNewThisSession = allEntries.where(
            (e) => _sensorDataStore.containsKey(e.unixTimestamp)
          ).length;

          setState(() {
            _sensorLogEntries = allEntries;
            _nfcStatus = 'Read ${allEntries.length} entries. Total stored: ${_sensorDataStore.length}.';
            _scanning = false;
            _progressDetail = null;
          });

          await nfc.NfcManager.instance.stopSession();

          // Show readout complete dialog
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Readout Complete'),
                content: Text(
                  'Read ${allEntries.length} entries.\n'
                  'Total stored: ${_sensorDataStore.length} data points.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          // Check if this is a connection dropped error
          final errorStr = e.toString().toLowerCase();
          final isConnectionDropped = errorStr.contains('taglost') ||
              errorStr.contains('tag lost') ||
              errorStr.contains('transceive') ||
              errorStr.contains('io exception') ||
              errorStr.contains('ioexception') ||
              errorStr.contains('connection') ||
              errorStr.contains('removed');

          setState(() {
            if (isConnectionDropped) {
              _nfcStatus = 'NFC connection dropped. Please try again.';
            } else {
              _nfcStatus = 'NFC error: $e';
            }
          });
          _disconnectTimer?.cancel();
          _disconnectTimer = Timer(const Duration(seconds: 3), () async {
            if (!mounted) return;
            setState(() {
              _scanning = false;
              _progressDetail = null;
              if (isConnectionDropped) {
                _nfcStatus = 'Connection lost. You can try again.';
              } else {
                _nfcStatus = 'NFC disconnected. You can try again.';
              }
            });
            try {
              await nfc.NfcManager.instance.stopSession();
            } catch (_) {}
          });
        }
      },
    );
  }

  // Show dialog with sensor data
  void _showSensorDataDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Sensor Data (${_sensorLogEntries.length} entries)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: _sensorLogEntries.length,
              itemBuilder: (context, index) {
                final entry = _sensorLogEntries[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    '${entry.sensorValue} µg/m³',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${entry.dateTime.toLocal()}${entry.rtcValid ? '' : ' (RTC invalid)'}',
                  ),
                  leading: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // _buildConfigBytes removed; using explicit memory-map writes instead.

  // _uploadConfigToNfc removed; merged into _connectToSensor

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
    const int cmdWriteSingleBlockExt =
        0x31; // ISO15693 Extended Write Single Block (16-bit block number)

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
      final int blockNumber = startBlock + i;
      final bool extended = blockNumber > 0xFF;
      frame.add([
        flags,
        extended ? cmdWriteSingleBlockExt : cmdWriteSingleBlock,
      ]);
      frame.add(
        uid,
      ); // UID as provided by Android API works for addressed mode on most devices
      if (extended) {
        // 16-bit block number, LSB first
        frame.add([blockNumber & 0xFF, (blockNumber >> 8) & 0xFF]);
      } else {
        frame.add([blockNumber & 0xFF]);
      }
      frame.add(block);

      final response = await v.transceive(frame.toBytes());
      // Optional: check response[0] == 0x00 (success) per ISO15693 response format
      if (response.isEmpty || response[0] != 0x00) {
        throw Exception(
          'Write block ${blockNumber} failed (resp: ${response.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
        );
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
    const int cmdReadSingleBlockExt =
        0x30; // ISO15693 Extended Read Single Block (16-bit block number)
    final blocksToRead = (length + blockSize - 1) ~/ blockSize;
    final out = BytesBuilder();
    for (int i = 0; i < blocksToRead; i++) {
      final frame = BytesBuilder();
      final int blockNumber = startBlock + i;
      final bool extended = blockNumber > 0xFF;
      frame.add([flags, extended ? cmdReadSingleBlockExt : cmdReadSingleBlock]);
      frame.add(uid);
      if (extended) {
        // 16-bit block number, LSB first
        frame.add([blockNumber & 0xFF, (blockNumber >> 8) & 0xFF]);
      } else {
        frame.add([blockNumber & 0xFF]);
      }
      final resp = await v.transceive(frame.toBytes());
      if (resp.isEmpty || resp[0] != 0x00) {
        throw Exception(
          'Read block ${blockNumber} failed (resp: ${resp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})',
        );
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
            if (_scanning) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              if (_progressDetail != null)
                Text(
                  _progressDetail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 16),
            ],
            // Show config summary if set
            if (_userName.isNotEmpty ||
                _warningLevel > 0 ||
                _maxLevel > 0 ||
                _lastWriteAddress != null)
              Column(
                children: [
                  if (_userName.isNotEmpty)
                    Text('User Name: $_userName', textAlign: TextAlign.center),
                  Text(
                    'Measure Mode: ${_measureMode == 0 ? '1 minute refresh' : '5 minutes refresh'}',
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Warning Level: $_warningLevel ug/m³',
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Max Level: $_maxLevel ug/m³',
                    textAlign: TextAlign.center,
                  ),
                  if (_lastTimestampWriteMs != null)
                    Text(
                      'Last timestamp write: ${DateTime.fromMillisecondsSinceEpoch(_lastTimestampWriteMs!).toLocal()}',
                      textAlign: TextAlign.center,
                    ),
                  if (_lastWriteAddress != null)
                    Text(
                      'Last Write Address: $_lastWriteAddress',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            Text(_nfcStatus, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_eepromData != null) ...[
              const Text(
                'EEPROM Data (hex):',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _eepromData!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 24),
            ],
            ElevatedButton.icon(
              onPressed: _scanning ? _stopScanning : _connectToSensor,
              icon: Icon(_scanning ? Icons.stop : Icons.sync),
              label: Text(_scanning ? 'Stop scanning' : 'Connect to sensor'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _readSensorValues,
              icon: const Icon(Icons.download),
              label: const Text('Read Sensor Values'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShowDataPage(sensorData: _sensorDataStore),
                  ),
                );
              },
              icon: const Icon(Icons.show_chart),
              label: Text('Show Data (${_sensorDataStore.length} points)'),
            ),
            if (_sensorLogEntries.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _showSensorDataDialog,
                child: Text('View ${_sensorLogEntries.length} sensor entries'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
