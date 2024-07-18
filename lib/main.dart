import 'package:android_esp32_bt_recording_app/BluetoothDeviceListEntry.dart';
import 'package:android_esp32_bt_recording_app/detailpage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  List<BluetoothDevice>? devices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
    _getBTState();
    _stateChangeListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      //resume
      if (_bluetoothState.isEnabled) {
        _listBondedDevices();
      }
    }
  }

  void _getBTState() {
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
      if (_bluetoothState.isEnabled) {
        _listBondedDevices();
      }
    });
  }

  void _stateChangeListener() {
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState.isEnabled) {
          _listBondedDevices();
        } else {
          devices?.clear();
        }
      });
    });
  }

  void _listBondedDevices() {
    FlutterBluetoothSerial.instance
        .getBondedDevices()
        .then((List<BluetoothDevice> bondedDevices) {
      setState(() {
        devices = bondedDevices;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("ESP32 Voice Recorder"),
      ),
      body: Container(
        child: Column(
          children: <Widget>[
            SwitchListTile(
              title: Text('Enable Bluetooth'),
              value: _bluetoothState.isEnabled,
              onChanged: (bool value) async {
                if (value) {
                  await FlutterBluetoothSerial.instance.requestEnable();
                } else {
                  await FlutterBluetoothSerial.instance.requestDisable();
                }
                setState(() {});
              },
            ),
            ListTile(
              title: Text("Bluetooth STATUS"),
              subtitle: Text(_bluetoothState.toString()),
              trailing: ElevatedButton(
                child: Text("Settings"),
                onPressed: () {
                  FlutterBluetoothSerial.instance.openSettings();
                },
              ),
            ),
            Expanded(
              child: ListView(
                children: devices!
                    .map((_device) => BluetoothDeviceListEntry(
                          device: _device,
                          enabled: true,
                          onTap: () {
                            _startCameraConnect(context, _device);
                          },
                        ))
                    .toList(),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _startCameraConnect(BuildContext context, BluetoothDevice server) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return DetailPage(server: server);
    }));
  }
}
