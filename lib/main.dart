import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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

  Future<void> _startNfcScan() async {
    setState(() {
      _nfcStatus = 'Scanning... Touch the ST25DV tag to the phone.';
      _eepromData = null;
      _scanning = true;
    });
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _nfcStatus = 'NFC is not available on this device.';
        _scanning = false;
      });
      return;
    }
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          // ST25DV is ISO 15693, but nfc_manager exposes raw data
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            setState(() {
              _nfcStatus = 'Tag is not NDEF formatted or not supported.';
              _scanning = false;
            });
            NfcManager.instance.stopSession();
            return;
          }
          await ndef.read();
          final cachedMessage = ndef.cachedMessage;
          if (cachedMessage == null) {
            setState(() {
              _nfcStatus = 'No NDEF message found.';
              _scanning = false;
            });
            NfcManager.instance.stopSession();
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
          NfcManager.instance.stopSession();
        } catch (e, stack) {
          // print('NFC read error: $e');
          // print('Stack trace: $stack');
          setState(() {
            _nfcStatus = 'Error reading tag: \$e';
            _scanning = false;
          });
          NfcManager.instance.stopSession(errorMessageIos: e.toString());
        }
      },
      pollingOptions: {NfcPollingOption.iso15693},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
          ],
        ),
      ),
    );
  }
}
