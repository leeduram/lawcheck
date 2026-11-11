import 'package:http/http.dart' as http;
import '../utils/log.dart';
import 'package:xml/xml.dart';
import '../models/law_result.dart';
import '../models/precedent_result.dart';
import 'secrets.dart';

class LegalService {
  static const String _apiKey = Secrets.lawOc;
  static const String _baseUrl = 'https://www.law.go.kr/DRF';
  static const _timeout = Duration(seconds: 8); // 모든 요청 타임아웃

  // ─────────────────────────────────────────
  // 법령 검색 (target=law)
  // ─────────────────────────────────────────

  /// 1단계: 법령 후보만 빠르게 수집 (법령명/ID만, 조문 조회 안 함)
  Future<List<Map<String, String>>> fetchLawCandidates(List<String> keywords) async {
    final candidates = <Map<String, String>>[];
    final seen = <String>{};

    for (final keyword in keywords) {
      try {
        final url = Uri.parse(
          '$_baseUrl/lawSearch.do?OC=$_apiKey&target=law&type=XML'
              '&query=${Uri.encodeComponent(keyword)}&display=5',
        );
        final response = await http.get(url).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final document = XmlDocument.parse(response.body);
        for (final law in document.findAllElements('law').take(4)) {
          final lawId = law.findElements('법령ID').firstOrNull?.innerText ?? '';
          final lawName = law.findElements('법령명한글').firstOrNull?.innerText ?? '';
          if (lawId.isEmpty || lawName.isEmpty || !seen.add(lawId)) continue;
          candidates.add({'lawId': lawId, 'lawName': lawName});
        }
      } catch (_) {
        continue;
      }
    }
    return candidates;
  }

  /// 3단계: 확정된 법령들의 조문 상세 조회
  Future<List<LawResult>> fetchLawDetails(
      List<Map<String, String>> confirmed, List<String> articleKeywords) async {
    final futures = confirmed.map((c) async {
      final lawId = c['lawId'] ?? '';
      final lawName = c['lawName'] ?? '';
      try {
        final article = await _fetchArticle(lawId, articleKeywords);
        if (article != null) {
          return LawResult(
            lawName: lawName,
            articleNo: article['articleNo'] ?? '',
            articleTitle: article['articleTitle'] ?? '',
            summary: article['content'] ?? '',
            lawId: lawId,
          );
        }
      } catch (_) {}
      return null;
    });

    final results = await Future.wait(futures);
    return results.whereType<LawResult>().toList();
  }

  Future<List<LawResult>> searchLaws(List<String> keywords) async {
    final results = <LawResult>[];
    for (final keyword in keywords) {
      try {
        final laws = await _searchLawByKeyword(keyword);
        results.addAll(laws);
        if (results.length >= 5) break;
      } catch (_) {
        continue;
      }
    }
    final seen = <String>{};
    return results.where((l) => seen.add(l.lawId)).take(5).toList();
  }

  Future<List<LawResult>> _searchLawByKeyword(String keyword) async {
    final url = Uri.parse(
      '$_baseUrl/lawSearch.do?OC=$_apiKey&target=law&type=XML'
          '&query=${Uri.encodeComponent(keyword)}&display=3',
    );

    final response = await http.get(url).timeout(_timeout);
    if (response.statusCode != 200) return [];

    final document = XmlDocument.parse(response.body);
    final laws = document.findAllElements('law');
    final results = <LawResult>[];

    for (final law in laws.take(2)) {
      final lawId = law.findElements('법령ID').firstOrNull?.innerText ?? '';
      final lawName = law.findElements('법령명한글').firstOrNull?.innerText ?? '';
      if (lawId.isEmpty || lawName.isEmpty) continue;
      try {
        final article = await _fetchArticle(lawId, [keyword]);
        if (article != null) {
          results.add(LawResult(
            lawName: lawName,
            articleNo: article['articleNo'] ?? '',
            articleTitle: article['articleTitle'] ?? '',
            summary: article['content'] ?? '',
            lawId: lawId,
          ));
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  Future<Map<String, String>?> _fetchArticle(
      String lawId, List<String> keywords) async {
    final url = Uri.parse(
      '$_baseUrl/lawService.do?OC=$_apiKey&target=law&ID=$lawId&type=XML',
    );

    final response = await http.get(url).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final document = XmlDocument.parse(response.body);
    final articles = document.findAllElements('조문단위').toList();
    if (articles.isEmpty) return null;

    // 목적조 찾기 (단순 장 제목 제외)
    String purposeContent = '';
    for (final article in articles) {
      final no = article.findElements('조문번호').firstOrNull?.innerText ?? '';
      final content = article.findElements('조문내용').firstOrNull?.innerText ?? '';
      if (no == '1' && content.isNotEmpty) {
        final cleaned = _cleanHtml(content);
        if (cleaned.contains('목적') || cleaned.contains('이 법은') ||
            cleaned.contains('이 영은') || cleaned.contains('이 규칙은')) {
          purposeContent = cleaned;
        }
        break;
      }
    }

    // [점수 기반] 모든 조문을 스캔해 키워드 매칭 점수가 가장 높은 조문 선택
    // 제목 일치 +3점, 내용 일치 +1점 (키워드당)
    // 2점 이상을 우선 채택, 없으면 1점짜리(차선)라도 사용
    String relatedNo = '';
    String relatedTitle = '';
    String relatedContent = '';
    int bestScore = 0;
    String fallbackNo = '';
    String fallbackTitle = '';
    String fallbackContent = '';
    for (final article in articles) {
      final no = article.findElements('조문번호').firstOrNull?.innerText ?? '';
      final title = article.findElements('조문제목').firstOrNull?.innerText ?? '';
      final content = article.findElements('조문내용').firstOrNull?.innerText ?? '';
      final cleanContent = _cleanHtml(content);
      if (no == '1' || cleanContent.length <= 20) continue;

      int score = 0;
      for (final kw in keywords) {
        final k = kw.trim();
        if (k.isEmpty) continue;
        if (title.contains(k)) score += 3;
        if (cleanContent.contains(k)) score += 1;
      }
      if (score >= 2 && score > bestScore) {
        bestScore = score;
        relatedNo = no;
        relatedTitle = title;
        relatedContent = cleanContent;
      } else if (score == 1 && fallbackNo.isEmpty) {
        // 1점짜리는 차선책으로 첫 번째 것만 기억
        fallbackNo = no;
        fallbackTitle = title;
        fallbackContent = cleanContent;
      }
    }
    // 2점 이상이 없으면 1점짜리 차선 사용
    if (relatedNo.isEmpty && fallbackNo.isNotEmpty) {
      relatedNo = fallbackNo;
      relatedTitle = fallbackTitle;
      relatedContent = fallbackContent;
      bestScore = 1;
    }
    if (bestScore > 0) {
      dlog('   📜 조문 선택: 제$relatedNo조 $relatedTitle (점수 $bestScore)');
    }

    // 목적조 + 관련조문 합치기
    final buffer = StringBuffer();
    if (purposeContent.isNotEmpty) buffer.write(purposeContent);
    if (relatedContent.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('제${relatedNo}조 $relatedTitle\n$relatedContent');
    }

    // 둘 다 없으면 내용 있는 2~10번째 조문 중 가장 긴 것
    if (buffer.isEmpty) {
      final candidates = articles.skip(1).take(10).map((a) {
        final no = a.findElements('조문번호').firstOrNull?.innerText ?? '';
        final title = a.findElements('조문제목').firstOrNull?.innerText ?? '';
        final content = _cleanHtml(a.findElements('조문내용').firstOrNull?.innerText ?? '');
        return {'no': no, 'title': title, 'content': content};
      }).where((a) => (a['content'] ?? '').length > 20).toList();

      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => (b['content'] ?? '').length.compareTo((a['content'] ?? '').length));
        final best = candidates.first;
        buffer.write('제${best['no']}조 ${best['title']}\n${best['content']}');
        relatedNo = best['no'] ?? '';
        relatedTitle = best['title'] ?? '';
      }
    }

    return {
      'articleNo': relatedNo.isNotEmpty ? relatedNo : '1',
      'articleTitle': relatedTitle.isNotEmpty ? relatedTitle : '',
      'content': buffer.toString(),
    };
  }

  /// 법령 전문 조회 (상세 화면용)
  Future<String> fetchFullLaw(String lawId) async {
    final url = Uri.parse(
      '$_baseUrl/lawService.do?OC=$_apiKey&target=law&ID=$lawId&type=XML',
    );
    final response = await http.get(url).timeout(_timeout);
    if (response.statusCode != 200) return '법령 정보를 불러올 수 없습니다.';

    final document = XmlDocument.parse(response.body);
    final buffer = StringBuffer();
    for (final article in document.findAllElements('조문단위')) {
      final no = article.findElements('조문번호').firstOrNull?.innerText ?? '';
      final title = article.findElements('조문제목').firstOrNull?.innerText ?? '';
      final content = _cleanHtml(article.findElements('조문내용').firstOrNull?.innerText ?? '');
      buffer.writeln('제${no}조 $title');
      buffer.writeln(content);
      buffer.writeln();
    }
    return buffer.toString();
  }

  // ─────────────────────────────────────────
  // 판례 검색 (target=prec)
  // ─────────────────────────────────────────

  /// [1단계] 사건명만 가볍게 수집 (상세조회 없음 → 빠름)
  /// 반환: [{caseNo, caseName, precId, courtName, judgDate, caseType}]
  Future<List<Map<String, String>>> collectPrecedentCandidates(
      List<String> keywords) async {
    final results = <Map<String, String>>[];
    final seen = <String>{};
    for (final keyword in keywords) {
      try {
        dlog('🔍 검색: "$keyword"');
        final url = Uri.parse(
          '$_baseUrl/lawSearch.do?OC=$_apiKey&target=prec&type=XML'
              '&query=${Uri.encodeComponent(keyword)}&display=30&sort=ddes&search=2'
              '&org=400201',
        );
        final response = await http.get(url).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final document = XmlDocument.parse(response.body);
        final tc = document.findAllElements('totalCnt').firstOrNull?.innerText ?? '?';
        dlog('   → "$keyword": $tc건');

        for (final c in document.findAllElements('prec')) {
          final caseNo = c.findElements('사건번호').firstOrNull?.innerText ?? '';
          final precId = c.findElements('판례일련번호').firstOrNull?.innerText ?? '';
          if (caseNo.isEmpty || precId.isEmpty) continue;
          if (!seen.add(caseNo)) {
            // 이미 수집된 판례 → 출신 쿼리만 누적 (검증 쿼리 역추적용)
            final existing = results.firstWhere(
                  (r) => r['caseNo'] == caseNo,
              orElse: () => {},
            );
            if (existing.isNotEmpty) {
              existing['sourceQuery'] = '${existing['sourceQuery']}||$keyword';
            }
            continue;
          }
          results.add({
            'caseNo': caseNo,
            'caseName': _cleanHtml(c.findElements('사건명').firstOrNull?.innerText ?? ''),
            'precId': precId,
            'courtName': c.findElements('법원명').firstOrNull?.innerText ?? '',
            'judgDate': c.findElements('선고일자').firstOrNull?.innerText ?? '',
            'caseType': c.findElements('사건종류명').firstOrNull?.innerText ?? '',
            'sourceQuery': keyword, // 어느 쿼리에서 나왔는지 기록 (2회전용)
          });
        }
      } catch (_) {
        continue;
      }
    }
    return results; // 모든 조합 검색 (조합당 30개, 중복 제거됨)
  }

  /// [2회전] 검증된 쿼리만 깊게 재검색 (display=100, 이미 본 판례 제외)
  Future<List<Map<String, String>>> deepCollectCandidates(
      List<String> queries, Set<String> excludeCaseNos) async {
    final results = <Map<String, String>>[];
    final seen = <String>{...excludeCaseNos};
    for (final keyword in queries) {
      try {
        dlog('🔍 [2회전] 깊은 검색: "$keyword"');
        final url = Uri.parse(
          '$_baseUrl/lawSearch.do?OC=$_apiKey&target=prec&type=XML'
              '&query=${Uri.encodeComponent(keyword)}&display=50&sort=ddes&search=2'
              '&org=400201',
        );
        final response = await http.get(url).timeout(_timeout);
        if (response.statusCode != 200) continue;

        final document = XmlDocument.parse(response.body);
        final tc = document.findAllElements('totalCnt').firstOrNull?.innerText ?? '?';
        dlog('   → [2회전] "$keyword": $tc건');

        for (final c in document.findAllElements('prec')) {
          final caseNo = c.findElements('사건번호').firstOrNull?.innerText ?? '';
          final precId = c.findElements('판례일련번호').firstOrNull?.innerText ?? '';
          if (caseNo.isEmpty || precId.isEmpty) continue;
          if (!seen.add(caseNo)) continue; // 1회전에서 본 것 제외
          results.add({
            'caseNo': caseNo,
            'caseName': _cleanHtml(c.findElements('사건명').firstOrNull?.innerText ?? ''),
            'precId': precId,
            'courtName': c.findElements('법원명').firstOrNull?.innerText ?? '',
            'judgDate': c.findElements('선고일자').firstOrNull?.innerText ?? '',
            'caseType': c.findElements('사건종류명').firstOrNull?.innerText ?? '',
            'sourceQuery': keyword,
          });
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  /// [3단계] 1차 선별 통과한 후보들만 상세조회 (판시사항+본문)
  Future<List<PrecedentResult>> fetchPrecedentDetails(
      List<Map<String, String>> candidates) async {
    final futures = candidates.map((c) async {
      final detail = await _fetchPrecedentDetail(c['precId'] ?? '');
      if (detail == null) return null; // 상세조회 실패 → 제외
      return PrecedentResult(
        caseNo: c['caseNo'] ?? '',
        courtName: c['courtName'] ?? '',
        judgDate: _formatDate((c['judgDate'] ?? '').replaceAll('.', '')),
        caseType: c['caseType'] ?? '',
        summary: detail['preview'] ?? '',
        fullContent: detail['fullContent'] ?? '',
        detailUrl:
        '$_baseUrl/lawService.do?OC=$_apiKey&target=prec&ID=${c['precId']}&type=HTML',
      );
    });
    final results = await Future.wait(futures);
    return results.whereType<PrecedentResult>().toList();
  }

  /// 판례 상세 조회 → {preview: 판시사항 발췌, fullContent: 판례내용 전문}
  /// 조회 실패 시 null (유효하지 않은 판례)
  Future<Map<String, String>?> _fetchPrecedentDetail(String precId) async {
    if (precId.isEmpty) return null;
    try {
      final url = Uri.parse(
        '$_baseUrl/lawService.do?OC=$_apiKey&target=prec&ID=$precId&type=XML',
      );
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode != 200) return null;

      // "일치하는 판례가 없습니다" 응답 걸러내기
      if (response.body.contains('일치하는 판례가 없습니다')) return null;

      final document = XmlDocument.parse(response.body);

      final issue = _cleanHtml(document.findAllElements('판시사항').firstOrNull?.innerText ?? '');
      final gist = _cleanHtml(document.findAllElements('판결요지').firstOrNull?.innerText ?? '');
      final content = _cleanHtml(document.findAllElements('판례내용').firstOrNull?.innerText ?? '');

      // 미리보기: 판시사항 우선, 없으면 판결요지
      final previewSource = issue.isNotEmpty ? issue : gist;
      if (previewSource.isEmpty && content.isEmpty) return null;

      final preview = previewSource.length > 300
          ? '${previewSource.substring(0, 300)}...'
          : previewSource;

      return {
        'preview': preview,
        'fullContent': content, // 클릭 시 AI 설명용 (공소사실+판결결과 추출)
      };
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────
  // 유틸
  // ─────────────────────────────────────────

  String _cleanHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatDate(String raw) {
    final cleaned = raw.replaceAll('.', '').replaceAll('-', '').trim();
    if (cleaned.length == 8) {
      return '${cleaned.substring(0, 4)}. ${cleaned.substring(4, 6)}. ${cleaned.substring(6, 8)}.';
    }
    return raw;
  }
}