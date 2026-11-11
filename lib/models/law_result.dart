class LawResult {
  final String lawName;        // 법령명
  final String articleNo;      // 조문번호 (예: 제36조)
  final String articleTitle;   // 조문제목
  final String summary;        // 발췌 원문 (목적조+관련조문, 클릭 시 AI설명용)
  final String previewSummary; // 카드 미리보기용 AI 요약 ("왜 만든 법인지")
  final String relevance;      // 내 상황과의 연결점 ("이 상황에서 이 법의 요점")
  final String lawId;          // 법령ID (상세 조회용)

  LawResult({
    required this.lawName,
    required this.articleNo,
    required this.articleTitle,
    required this.summary,
    this.previewSummary = '',
    this.relevance = '',
    required this.lawId,
  });

  LawResult copyWith({String? previewSummary, String? relevance}) => LawResult(
    lawName: lawName,
    articleNo: articleNo,
    articleTitle: articleTitle,
    summary: summary,
    previewSummary: previewSummary ?? this.previewSummary,
    relevance: relevance ?? this.relevance,
    lawId: lawId,
  );

  Map<String, dynamic> toJson() => {
    'lawName': lawName,
    'articleNo': articleNo,
    'articleTitle': articleTitle,
    'summary': summary,
    'previewSummary': previewSummary,
    'relevance': relevance,
    'lawId': lawId,
  };

  factory LawResult.fromJson(Map<String, dynamic> json) => LawResult(
    lawName: json['lawName'] ?? '',
    articleNo: json['articleNo'] ?? '',
    articleTitle: json['articleTitle'] ?? '',
    summary: json['summary'] ?? '',
    previewSummary: json['previewSummary'] ?? '',
    relevance: json['relevance'] ?? '',
    lawId: json['lawId'] ?? '',
  );
}