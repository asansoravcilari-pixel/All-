import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpectreVisionApp());
}

class SpectreVisionApp extends StatelessWidget {
  const SpectreVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPECTRE Duo Vision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C5CE7),
          surface: Color(0xFF131A2E),
        ),
      ),
      home: const VisionAssistantScreen(),
    );
  }
}

class VisionAssistantScreen extends StatefulWidget {
  const VisionAssistantScreen({super.key});

  @override
  State<VisionAssistantScreen> createState() => _VisionAssistantScreenState();
}

class _VisionAssistantScreenState extends State<VisionAssistantScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _serverCtrl = TextEditingController(text: 'http://212.68.34.166:8000');
  final TextEditingController _promptCtrl = TextEditingController();

  bool _isListening = false;
  bool _isLoading = false;
  bool _shareScreenOnSend = true;
  final List> _messages = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();
  }

  void _initTts() async {
    await _tts.setLanguage('tr-TR');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverCtrl.text = prefs.getString('vision_server') ?? 'http://212.68.34.166:8000';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vision_server', _serverCtrl.text.trim());
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_promptCtrl.text.trim().isNotEmpty) {
        _analyzeAndSend(_promptCtrl.text.trim());
      }
    } else {
      var status = await Permission.microphone.request();
      if (!status.isGranted) return;

      bool available = await _speech.initialize(
        onError: (_) => setState(() => _isListening = false),
        onStatus: (st) {
          if (st == 'done' && _isListening) {
            setState(() => _isListening = false);
            if (_promptCtrl.text.trim().isNotEmpty) {
              _analyzeAndSend(_promptCtrl.text.trim());
            }
          }
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
          _promptCtrl.clear();
        });
        _speech.listen(
          localeId: 'tr_TR',
          listenMode: ListenMode.dictation,
          onResult: (result) {
            setState(() {
              _promptCtrl.text = result.recognizedWords;
            });
          },
        );
      }
    }
  }

  Future<void> _analyzeAndSend(String query) async {
    setState(() {
      _messages.add({'role': 'user', 'text': query});
      _messages.add({'role': 'assistant', 'text': 'Ekran inceleniyor ve araştırılıyor...'});
      _isLoading = true;
    });

    String? base64Image;

    if (_shareScreenOnSend) {
      try {
        final tempDir = await getTemporaryDirectory();
        final imagePath = '${tempDir.path}/screenshot.png';
        final captured = await ScreenCapturer.instance.capture(
          mode: CaptureMode.screen,
          imagePath: imagePath,
          silent: true,
        );
        if (captured != null) {
          final file = File(captured.imagePath!);
          final bytes = await file.readAsBytes();
          base64Image = base64Encode(bytes);
        }
      } catch (_) {}
    }

    try {
      final res = await http.post(
        Uri.parse('${_serverCtrl.text.trim()}/api/vision/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': query,
          'image_base64': base64Image,
        }),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final reply = data['comment'] ?? 'Analiz yapılamadı.';

        setState(() {
          _messages.last['text'] = reply;
          _isLoading = false;
        });

        await _tts.speak(reply);
      } else {
        setState(() {
          _messages.last['text'] = 'Sunucu Hatası: ${res.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.last['text'] = 'Bağlantı Hatası: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SPECTRE • Pair Programmer'),
        backgroundColor: const Color(0xFF0F1527),
        actions: [
          Row(
            children: [
              const Text('Ekranı Gör:', style: TextStyle(fontSize: 12)),
              Switch(
                value: _shareScreenOnSend,
                activeColor: const Color(0xFFA29BFE),
                onChanged: (val) => setState(() => _shareScreenOnSend = val),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, idx) {
                final m = _messages[idx];
                final isUser = m['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF6C5CE7) : const Color(0xFF1E2846),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      m['text'] ?? '',
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF0F1527),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isListening ? (_promptCtrl.text.isEmpty ? 'Dinliyor... Ekrandaki durumu anlatın' : _promptCtrl.text) : 'Konuşmak için mikrofona dokunun',
                    style: TextStyle(
                      color: _isListening ? Colors.redAccent : Colors.grey,
                      fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: _isListening ? Colors.redAccent : const Color(0xFF6C5CE7),
                  onPressed: _toggleMic,
                  child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A2E),
        title: const Text('Ubuntu Sunucu Adresi'),
        content: TextField(
          controller: _serverCtrl,
          decoration: const InputDecoration(labelText: 'Sunucu URL (Örn: http://IP:8000)'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
