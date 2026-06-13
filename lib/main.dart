import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';

void main() => runApp(const ChatAskiApp());

/* ── data ── */
class Msg {
  final String? id;
  final String role;
  String content;
  final int ts;
  Msg({this.id, required this.role, this.content = '', int? ts}) : ts = ts ?? DateTime.now().millisecondsSinceEpoch;
}

class Mx {
  const Mx(this.k, this.l);
  final String k;
  final String l;
}

const _modelList = [
  Mx('qwen3.6:27b', 'Qwen 3.6 (27B)'),
  Mx('qwen3-coder:30b', 'Qwen Coder (30B)'),
];

String _ollamaUrl() => const String.fromEnvironment('OLLAMA_URL', defaultValue: 'http://localhost:11434');

Stream<String> _streamChat(List<Msg> msgs, String model) async* {
  final uri = '${_ollamaUrl()}/api/chat';
  final payload = jsonEncode({
    'model': model,
    'messages': [for (final m in msgs) if (m.content.isNotEmpty) {'role': m.role, 'content': m.content}],
    'stream': true,
  });

  final req = await html.window.fetch(
    uri, {
      'method': 'POST' as dynamic,
      'headers': {'Content-Type': 'application/json'},
      'body': payload,
    },
  );

  if (!req.ok) {
    throw Exception('Ollama error ${req.status}');
  }

  final text = await req.text;
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final j = jsonDecode(trimmed);
      final delta = (j['message'] as Map?)?['content'] ?? '';
      if (delta is String && delta.isNotEmpty) yield delta;
    } catch (_) {}
  }
}

const _bgColor = Color(0xFF222224);
const _accent = Color(0xFF6366F1);

/* ── app shell ── */
class ChatAskiApp extends StatelessWidget {
  const ChatAskiApp({super.key});

  @override
  Widget build(BuildContext ctx) {
    return MaterialApp(
      title: 'Chat Aski',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark, surface: _bgColor),
        scaffoldBackgroundColor: _bgColor,
        appBarTheme: const AppBarTheme(centerTitle: true, backgroundColor: _bgColor),
      ),
      home: const ChatScreen(),
    );
  }
}

/* ── chat screen ── */
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ScreenState();
}

class _ScreenState extends State<ChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _sCtrl = ScrollController();
  final List<Msg> _messages = [];
  String _modelKey = 'qwen3.6:27b';
  bool _isSending = false;
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _modelKey = _modelList.first.k;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _sCtrl.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(Msg(role: 'user', content: text));
      _textCtrl.clear();
      _isSending = true;
    });

    final aiMsgId = 'ai-${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _messages.add(Msg(id: aiMsgId, role: 'assistant')));

    try {
      final contextMessages = _messages.where((m) => m.content.isNotEmpty).toList();
      await for (final delta in _streamChat(contextMessages, _modelKey)) {
        if (!mounted) break;

        final idx = _messages.indexWhere((m) => m.id == aiMsgId);
        if (idx < 0) break;

        setState(() {
          _messages[idx] = Msg(id: _messages[idx].id, role: 'assistant', content: _messages[idx].content + delta);
        });

        _scrollTimer?.cancel();
        _scrollTimer = Timer(const Duration(milliseconds: 200), () {
          if (_sCtrl.hasClients) {
            _sCtrl.animateTo(
              _sCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (err) {
      final idx = _messages.indexWhere((m) => m.id == aiMsgId);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = Msg(id: _messages[idx].id, role: 'assistant', content: '\u274C $err');
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollTimer?.cancel();
    }
  }

  Widget _welcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(color: _accent.withAlpha(30), borderRadius: BorderRadius.circular(24)),
            alignment: Alignment.center,
            child: const Icon(Icons.smart_toy_rounded, size: 60, color: _accent),
          ),
          const SizedBox(height: 20),
          Text('채팅을 시작해보세요 \u2728', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('로컬 AI 모델을 활용합니다', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _messageBubble(Msg msg, int index) {
    final isUser = msg.role == 'user';
    final timeFormatted = _formatTime(msg.ts);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 750),
        margin: EdgeInsets.only(top: index == 0 ? 8 : 12, left: isUser ? 48 : 16, right: isUser ? 16 : 48),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser && msg.content.isEmpty)
              Container(height: 24, alignment: Alignment.centerLeft, child: LinearProgressIndicator(color: _accent))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser ? _accent : Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 4 : 18),
                    topRight: Radius.circular(isUser ? 18 : 4),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Text(
                  msg.content.isEmpty ? '(비어있음)' : msg.content,
                  style: TextStyle(color: isUser ? Colors.white : Colors.white70, fontSize: 14.5, height: 1.5),
                ),
              ),
            const SizedBox(height: 4),
            Text(timeFormatted, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext ctx) {
    final mq = MediaQuery.of(ctx);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chat_bubble_rounded, color: _accent, size: 26),
          const SizedBox(width: 8),
          Text('Chat Aski', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          DropdownButton<String>(
            value: _modelKey,
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
            items: _modelList.map((e) => DropdownMenuItem(value: e.k, child: Text(e.l, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: _isSending ? null : (v) { if (v != null) setState(() => _modelKey = v); },
          ),
          IconButton(icon: const Icon(Icons.add_chart_rounded), onPressed: _isSending ? null : () => setState(_messages.clear)),
        ]),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: _bgColor, border: Border(top: BorderSide(color: Colors.white.withAlpha(20)))),
        padding: EdgeInsets.fromLTRB(12, 8, 16, mq.padding.bottom + 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              maxLines: null,
              enabled: !_isSending,
              cursorColor: _accent,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '메시지 입력...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                filled: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (v) => _isSending || v.trim().isEmpty ? null : _sendMessage(v),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            decoration: BoxDecoration(
              color: (_textCtrl.text.trim().isEmpty || _isSending) ? const Color(0xFF333) : _accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(_isSending ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: () => _sendMessage(_textCtrl.text),
            ),
          ),
        ]),
      ),
      body: _messages.isEmpty ? _welcomeScreen() : Expanded(
        child: ListView.builder(
          controller: _sCtrl,
          padding: EdgeInsets.only(top: mq.padding.top + kToolbarHeight + 16, bottom: 20),
          itemCount: _messages.length,
          itemBuilder: (_, i) => _messageBubble(_messages[i], i),
        ),
      ),
    );
  }
}
