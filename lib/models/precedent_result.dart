class PrecedentResult {
  final String caseNo;       // 사건번호 (예: 대법원 2019도1234)
  final String courtName;    // 법원명
  final String judgDate;     // 선고일
  final String caseType;     // 사건종류
  final String summary;      // 미리보기 (판시사항 발췌)
  final String fullContent;  // 판례내용 전문 (클릭 시 AI 설명용)
  final String detailUrl;    // 상세 링크

  PrecedentResult({
    required this.caseNo,
    required this.courtName,
    required this.judgDate,
    required this.caseType,
    required this.summary,
    this.fullContent = '',
    required this.detailUrl,
  });

  PrecedentResult copyWith({String? summary}) => PrecedentResult(
    caseNo: caseNo,
    courtName: courtName,
    judgDate: judgDate,
    caseType: caseType,
    summary: summary ?? this.summary,
    fullContent: fullContent,
    detailUrl: detailUrl,
  );

  Map<String, dynamic> toJson() => {
    'caseNo': caseNo,
    'courtName': courtName,
    'judgDate': judgDate,
    'caseType': caseType,
    'summary': summary,
    'fullContent': fullContent,
    'detailUrl': detailUrl,
  };

  factory PrecedentResult.fromJson(Map<String, dynamic> json) =>
      PrecedentResult(
        caseNo: json['caseNo'] ?? '',
        courtName: json['courtName'] ?? '',
        judgDate: json['judgDate'] ?? '',
        caseType: json['caseType'] ?? '',
        summary: json['summary'] ?? '',
        fullContent: json['fullContent'] ?? '',
        detailUrl: json['detailUrl'] ?? '',
      );
}