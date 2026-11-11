import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_item.dart';

class HistoryService {
  static const String _key = 'lawcheck_history';

  /// 전체 히스토리 불러오기 (최신순)
  Future<List<HistoryItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => HistoryItem.fromJson(jsonDecode(s)))
        .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 새 항목 저장
  Future<void> save(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(item.toJson()));
    await prefs.setStringList(_key, raw);
  }

  /// 특정 항목 삭제
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m['id'] == id;
    });
    await prefs.setStringList(_key, raw);
  }

  /// 전체 삭제
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
