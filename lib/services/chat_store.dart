import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class ChatStore {
  static const _key = 'arzu_code_chat_sessions_v1';

  Future<List<ChatSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final parsed = list
          .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Bo'sh sessionlarni tozalash
      parsed.removeWhere((s) => s.messages.isEmpty && s.title == 'New session');
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final list = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}