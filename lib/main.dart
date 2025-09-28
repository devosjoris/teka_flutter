import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart' as nfc;
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart' as ndef;
import 'dart:typed_data';
import 'dart:convert';
import 'package:nfc_manager/ndef_record.dart' as ndefrec;

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

  // Config fields
  String _userName = '';
  String _userCompany = '';
  String _sensorSetting = 'low';

  Future<void> _showConfigDialog() async {
    final nameController = TextEditingController(text: _userName);
    final companyController = TextEditingController(text: _userCompany);
    String dropdownValue = _sensorSetting;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'User Name'),
              ),
              TextField(
                controller: companyController,
                decoration: const InputDecoration(labelText: 'User Company'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: dropdownValue,
                decoration: const InputDecoration(labelText: 'Sensor Setting'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    dropdownValue = value;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _userName = nameController.text;
                  _userCompany = companyController.text;
                  _sensorSetting = dropdownValue;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

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
          // ST25DV is ISO 15693, but nfc_manager exposes raw data
          final ndefTag = ndef.Ndef.from(tag);
          if (ndefTag == null) {
            setState(() {
              _nfcStatus = 'Tag is not NDEF formatted or not supported.';
              _scanning = false;
            });
            nfc.NfcManager.instance.stopSession();
            return;
          }
          await ndefTag.read();
          final cachedMessage = ndefTag.cachedMessage;
          if (cachedMessage == null) {
            setState(() {
              _nfcStatus = 'No NDEF message found.';
              _scanning = false;
            });
            nfc.NfcManager.instance.stopSession();
            return;
          }
          // For demo: show payload as hex string
          final payloads = cachedMessage.records.map((r) => r.payload).toList();
          String hexData = payloads.map((b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')).join('\n');
          setState(() {
            _eepromData = hexData;
            _nfcStatus = 'EEPROM data read!';
            _scanning = false;
          });
          nfc.NfcManager.instance.stopSession();
        } catch (e) {
          // print('NFC read error: $e');
          // print('Stack trace: $stack');
          setState(() {
            _nfcStatus = 'Error reading tag: $e';
            _scanning = false;
          });
          nfc.NfcManager.instance.stopSession(errorMessageIos: e.toString());
        }
      },
      pollingOptions: {nfc.NfcPollingOption.iso15693},
    );
  }

  // Helper to encode config as bytes for EEPROM
  List<int> _buildConfigBytes() {
    List<int> nameBytes = List.filled(50, 0);
    List<int> companyBytes = List.filled(50, 0);
    List<int> userNameBytes = _userName.codeUnits;
    List<int> userCompanyBytes = _userCompany.codeUnits;
    for (int i = 0; i < userNameBytes.length && i < 50; i++) {
      nameBytes[i] = userNameBytes[i];
    }
    for (int i = 0; i < userCompanyBytes.length && i < 50; i++) {
      companyBytes[i] = userCompanyBytes[i];
    }
    int sensorSettingByte = 0;
    switch (_sensorSetting) {
      case 'low':
        sensorSettingByte = 0;
        break;
      case 'medium':
        sensorSettingByte = 1;
        break;
      case 'high':
        sensorSettingByte = 2;
        break;
    }
    return [...nameBytes, ...companyBytes, sensorSettingByte];
  }

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
          final ndefTag = ndef.Ndef.from(tag);
          if (ndefTag == null || !ndefTag.isWritable) {
            setState(() {
              _nfcStatus = 'Tag is not NDEF writable or not supported.';
              _scanning = false;
            });
            nfc.NfcManager.instance.stopSession();
            return;
          }
          List<int> configBytes = _buildConfigBytes();
          // Write raw config bytes as an NDEF media (MIME) record.
          final record = ndefrec.NdefRecord(
            typeNameFormat: ndefrec.TypeNameFormat.media,
            type: Uint8List.fromList(ascii.encode('application/octet-stream')),
            identifier: Uint8List(0),
            payload: Uint8List.fromList(configBytes),
          );
          final message = ndefrec.NdefMessage(records: [record]);
          await ndefTag.write(message: message);
          setState(() {
            _nfcStatus = 'Config uploaded to NFC!';
            _scanning = false;
          });
          nfc.NfcManager.instance.stopSession();
        } catch (e) {
          setState(() {
            _nfcStatus = 'Error uploading config: $e';
            _scanning = false;
          });
          nfc.NfcManager.instance.stopSession(errorMessageIos: e.toString());
        }
      },
      pollingOptions: {nfc.NfcPollingOption.iso15693},
    );
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
            onPressed: _showConfigDialog,
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
            if (_userName.isNotEmpty || _userCompany.isNotEmpty)
              Column(
                children: [
                  if (_userName.isNotEmpty)
                    Text('User Name: $_userName', textAlign: TextAlign.center),
                  if (_userCompany.isNotEmpty)
                    Text('User Company: $_userCompany', textAlign: TextAlign.center),
                  Text('Sensor Setting: ${_sensorSetting[0].toUpperCase()}${_sensorSetting.substring(1)}', textAlign: TextAlign.center),
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
