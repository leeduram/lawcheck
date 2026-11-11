import 'law_result.dart';
import 'precedent_result.dart';

class HistoryItem {
  final String id;           // 고유 ID (timestamp 기반)
  final String query;        // 사용자 입력 질문
  final String advice;       // Gemini 조언 (1~2문장)
  final DateTime createdAt;  // 검색 시각
  final List<LawResult> laws;             // 저장된 법령 결과
  final List<PrecedentResult> precedents; // 저장된 판례 결과

  HistoryItem({
    required this.id,
    required this.query,
    required this.advice,
    required this.createdAt,
    required this.laws,
    required this.precedents,
  });

  // SharedPreferences 저장용 JSON 직렬화
  Map<String, dynamic> toJson() => {
    'id': id,
    'query': query,
    'advice': advice,
    'createdAt': createdAt.toIso8601String(),
    'laws': laws.map((l) => l.toJson()).toList(),
    'precedents': precedents.map((p) => p.toJson()).toList(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    id: json['id'] ?? '',
    query: json['query'] ?? '',
    advice: json['advice'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
    laws: (json['laws'] as List<dynamic>? ?? [])
        .map((e) => LawResult.fromJson(e as Map<String, dynamic>))
        .toList(),
    precedents: (json['precedents'] as List<dynamic>? ?? [])
        .map((e) => PrecedentResult.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}