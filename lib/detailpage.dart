import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:android_esp32_bt_recording_app/wav_header.dart';
import 'package:android_esp32_bt_recording_app/file_entity_list_tile.dart';
import 'package:async/async.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

enum RecordState { stopped, recording }

class DetailPage extends StatefulWidget {
  final BluetoothDevice? server;

  const DetailPage({this.server});

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  BluetoothConnection? connection;
  bool isConnecting = true;
  bool get isConnected => connection != null && connection!.isConnected;
  bool isDisconnecting = false;
  List<List<int>> chunks = <List<int>>[];
  int contentLength = 0;
  Uint8List? _bytes;
  RestartableTimer? _timer;
  RecordState _recordState = RecordState.stopped;
  DateFormat dateFormat = DateFormat("yyyy-MM-dd_HH_mm_ss");
  List<FileSystemEntity> files = List<FileSystemEntity>.empty(growable: true);
  String? selectedFilePath;
  AudioPlayer player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _getBTConnection();
    _timer = RestartableTimer(Duration(seconds: 1), _completeByte);
    _listofFiles();
    selectedFilePath = '';
  }

  @override
  void dispose() {
    if (isConnected) {
      isDisconnecting = true;
      connection!.dispose();
      connection = null;
    }
    _timer!.cancel();
    super.dispose();
  }

  _getBTConnection() {
    BluetoothConnection.toAddress(widget.server!.address).then((_connection) {
      connection = _connection;
      isConnecting = false;
      isDisconnecting = false;
      setState(() {});
      connection!.input!.listen(_onDataReceived).onDone(() {
        if (isDisconnecting) {
          print('Disconnecting locally');
        } else {
          print('Disconnecting remotely');
        }
        if (this.mounted) {
          setState(() {});
        }
        Navigator.of(context).pop();
      });
    }).catchError((error) {
      Navigator.of(context).pop();
    });
  }

  _completeByte() async {
    if (chunks.isEmpty || contentLength == 0) return;
    print("CompleteByte length : $contentLength");
    _bytes = Uint8List(contentLength);
    int offset = 0;
    for (final List<int> chunk in chunks) {
      _bytes!.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    final file = await _makeNewFile;
    var headerList = WavHeader.createWavHeader(contentLength);
    file.writeAsBytesSync(headerList, mode: FileMode.write);
    file.writeAsBytesSync(_bytes!, mode: FileMode.append);
    print(await file.length());
    _listofFiles();
    contentLength = 0;
    chunks.clear();
  }

  void _onDataReceived(Uint8List data) {
    if (data.isNotEmpty) {
      chunks.add(data);
      contentLength += data.length;
      _timer!.reset();
    }
    print("Data Length: ${data.length}, chunks: ${chunks.length}");
  }

  void _sendMessage(String text) async {
    text = text.trim();
    if (text.isNotEmpty) {
      try {
        connection!.output.add(utf8.encode(text));
        await connection!.output.allSent;
        if (text == "START") {
          _recordState = RecordState.recording;
        } else if (text == "STOP") {
          _recordState = RecordState.stopped;
        }
        setState(() {});
      } catch (e) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: (isConnecting
              ? Text('Connecting to ${widget.server!.name} ...')
              : isConnected
                  ? Text('Connected with ${widget.server!.name}')
                  : Text('Disconnected with ${widget.server!.name}')),
        ),
        body: SafeArea(
          child: isConnected
              ? Column(
                  children: <Widget>[
                    shotButton(),
                    Expanded(
                      child: ListView(
                        children: files
                            .map((_file) => FileEntityListTile(
                                  filePath: _file.path,
                                  fileSize: _file.statSync().size,
                                  onLongPress: () async {
                                    print("onLongPress item");
                                    if (await File(_file.path).exists()) {
                                      File(_file.path).deleteSync();
                                      files.remove(_file);
                                      setState(() {});
                                    }
                                  },
                                  onTap: () async {
                                    print("onTap item");
                                    if (_file.path == selectedFilePath) {
                                      await player.stop();
                                      selectedFilePath = '';
                                      return;
                                    }
                                    if (await File(_file.path).exists()) {
                                      selectedFilePath = _file.path;
                                      await player
                                          .play(AssetSource(_file.path));
                                      // await player.start(_file.path);
                                    } else {
                                      selectedFilePath = '';
                                    }
                                    setState(() {});
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Text(
                    "Connecting...",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
        ));
  }

  Widget shotButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.red),
          ),
        ),
        onPressed: () {
          if (_recordState == RecordState.stopped) {
            _sendMessage("START");
            _showRecordingDialog();
          } else {
            _sendMessage("STOP");
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            _recordState == RecordState.stopped ? "RECORD" : "STOP",
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }

  void _showRecordingDialog() {
    SmartDialog.show(
      alignment: Alignment.center,
      clickMaskDismiss: false,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            Text(
              "Recording",
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 40),
            Container(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                strokeWidth: 10,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
            SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.red),
                ),
              ),
              onPressed: () {
                _sendMessage("STOP");
                SmartDialog.dismiss();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  "STOP",
                  style: TextStyle(fontSize: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _makeNewFile async {
    final path = await _localPath;
    String newFileName = dateFormat.format(DateTime.now());
    return File('$path/$newFileName.wav');
  }

  void _listofFiles() async {
    final path = await _localPath;
    var fileList = Directory(path).list();
    files.clear();
    await for (var element in fileList) {
      if (element.path.contains("wav")) {
        files.insert(0, element);
        print("PATH: ${element.path} Size: ${element.statSync().size}");
      }
    }
    setState(() {});
  }
}
