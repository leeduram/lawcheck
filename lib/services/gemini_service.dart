import 'dart:convert';
import '../utils/log.dart';
import 'package:http/http.dart' as http;
import 'secrets.dart';

class GeminiService {
  // 키는 secrets.dart 에 둔다 (깃허브에 올리지 않음)
  static const String _apiKey = Secrets.geminiApiKey;
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent';

  /// 법령 + 판례 검색 키워드를 한 번에 생성 (호출 1회)
  /// 반환: {law: [...], precedent: [...], caseNos: [...]}
  Future<Map<String, List<String>>> extractKeywords(String userInput) async {
    final prompt = '''
사용자의 상황을 분석해서 대한민국 법령 검색용 키워드, 판례 검색용 키워드, 그리고 관련 판례 사건번호를 생성하세요.

[사용자 입력]
"$userInput"

[법령 키워드 규칙]
- 실제 대한민국 법령명에 들어가는 단어.
- 예: "치킨집 창업" → ["식품위생법", "소방시설", "위생관리"]
- 예: "유튜브 수익 군인" → ["군인사법", "국가공무원법", "소득세법"]
- 최대 4개.

[조문 키워드 규칙]
- 찾아낸 법령 "안에서 어떤 조문을 보여줄지" 찾는 데 쓰입니다. 조문 제목이나 내용에 등장할 쟁점 단어를 뽑으세요.
- 법령명이 아니라, 사용자 상황의 법적 쟁점을 나타내는 단어입니다.
- 예: "보증금에서 도배비 빼겠다는 집주인" → ["원상회복", "보증금", "수선", "반환"]
- 예: "공무원인데 유튜브 수익" → ["영리", "겸직", "복무"]
- 예: "익명 채팅앱 운영" → ["불법정보", "음란", "삭제", "개인정보"]
- 최대 4개.

[판례 키워드 규칙]
- 판례 본문 검색용 "검색 쿼리"를 직접 만드세요. 각 쿼리는 두 단어를 공백으로 묶은 형태이며, 두 단어가 모두 포함된 판례만 검색됩니다(AND).
- ★판례 본문은 법률 문어체입니다. 판결문에 실제 등장할 법률 용어로 만드세요.
  - 일상어 → 법률어: "중고거래"→"매매", "해외직구 전자제품"→"전기용품"/"적합성평가", "유튜브 부업"→"겸직"/"영리업무", "따돌림"→"학교폭력"/"괴롭힘"
- ★의미 있는 조합만 만드세요. 두 단어가 한 사건에서 자연스럽게 같이 등장할 조합이어야 합니다.
  - 좋은 조합: "겸직 영리업무", "공무원 겸직", "학교폭력 손해배상", "안전인증 판매"
  - 나쁜 조합: "금지 징계", "위반 책임" (둘 다 너무 일반적이라 무관한 판례만 걸림)
- 서로 다른 각도의 조합을 5~8개 만드세요. (같은 단어쌍 반복 금지)
- 예: "공무원이 유튜브로 수익" → ["공무원 겸직", "겸직 영리업무", "공무원 영리업무", "겸직허가 위반", "영리업무 징계"]
- 예: "해외직구 폰을 중고로 판매" → ["전기용품 안전인증", "적합성평가 판매", "형식승인 수입", "전파법 판매", "안전인증 미필"]
- 최대 8개.

[판례 사건번호 규칙]
- 사용자 상황과 가장 유사한 실제 대한민국 판례의 사건번호를 아는 만큼 나열하세요.
- 형식 예: "2025다211430", "2023도1234", "2020두5678", "2019구합12345"
- 확실하지 않아도 가능성 있는 것을 폭넓게 최대 10개까지 제시하세요.
- 실제 존재 여부는 시스템이 검증하므로 부담 없이 나열하세요.
- 모르면 빈 배열.

[조문 키워드 규칙]
- 확정된 법령 안에서 "사용자 상황과 관련된 조문"을 찾는 데 쓰입니다.
- 조문 제목/내용에 실제 등장할 법률 개념 단어를 한 단어씩 3~5개.
- 예: "보증금에서 도배비 빼고 준다" → ["원상회복", "보증금", "수선", "손해배상"]
- 예: "공무원이 유튜브 수익" → ["영리", "겸직", "복무"]
- 예: "해외직구 폰 판매" → ["적합성평가", "안전인증", "판매"]

[출력] - 반드시 아래 JSON만 반환, 다른 텍스트 없이
{"law": ["...", "..."], "precedent": ["...", "..."], "article": ["...", "..."], "caseNos": []}
''';

    final response = await _callGemini(prompt);
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      final law = (parsed['law'] as List<dynamic>? ?? []).cast<String>();
      final precedent = (parsed['precedent'] as List<dynamic>? ?? []).cast<String>();
      final article = (parsed['article'] as List<dynamic>? ?? []).cast<String>();
      final caseNos = (parsed['caseNos'] as List<dynamic>? ?? []).cast<String>();
      return {
        'law': law.isNotEmpty ? law : userInput.split(' ').take(3).toList(),
        'precedent': precedent.isNotEmpty ? precedent : law,
        'article': article,
        'caseNos': caseNos,
      };
    } catch (_) {
      final fallback = userInput.split(' ').take(3).toList();
      return {'law': fallback, 'precedent': fallback, 'article': [], 'caseNos': []};
    }
  }

  List<String> _parseKeywords(String response, String fallback) {
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed.cast<String>();
    } catch (_) {
      return fallback.split(' ').take(3).toList();
    }
  }

  /// 후보 법령/판례 중 질문과 관련있는 것만 골라 인덱스 반환
  /// candidates: ["0: 동물보호법 - 동물판매업", "1: 동물약사법 - 정의", ...]
  Future<List<int>> rerank(String userInput, List<String> candidates,
      {bool lenient = false}) async {
    if (candidates.isEmpty) return [];

    final rule = lenient
        ? '''
- 사용자 상황과 조금이라도 참고가 될 만한 항목은 포함하세요.
- 분야나 쟁점이 비슷하면 상황이 완전히 똑같지 않아도 포함하세요.
- 명백히 무관한 항목(전혀 다른 분야)만 제외하세요.
- 관련도 높은 순으로 정렬하세요.'''
        : '''
- 사용자 상황과 직접 관련된 항목의 번호만 고르세요.
- 관련 없는 항목은 제외하세요. 억지로 포함하지 마세요.
- 관련도 높은 순으로 정렬하세요.''';

    final prompt = '''
사용자의 상황과 관련된 항목을 골라주세요.

[사용자 상황]
"$userInput"

[후보 목록]
${candidates.join('\n')}

[규칙]
$rule
- JSON 숫자 배열만 반환. 예: [2, 0, 5]
- 적절한 항목이 없으면 빈 배열 []
''';

    final response = await _callGemini(prompt);
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed.map((e) => e as int).toList();
    } catch (_) {
      return List.generate(candidates.length, (i) => i);
    }
  }

  /// [2단계] 1차 선별 — 사건명만 보고 "관련 가능성 있는 것" 거칠게 고름 (최대 15개)
  /// 정밀 판단은 2차(판시사항)에서 하므로 여기선 넓게 통과시킴
  Future<List<int>> prefilterPrecedents(
      String userInput, List<String> caseNames) async {
    if (caseNames.isEmpty) return [];

    final prompt = '''
사용자 상황과 관련 "가능성"이 있는 판례를 사건명만 보고 골라주세요.
지금은 1차 거름망입니다. 정밀 판단은 다음 단계에서 하므로, 조금이라도 관련 가능성이 보이면 포함하세요.

[사용자 상황]
"$userInput"

[판례 후보] (번호: 사건명)
${caseNames.join('\n')}

[기준]
- 사용자 상황과 같은 분야/쟁점일 가능성이 보이면 포함 (관대하게).
- 명백히 전혀 다른 분야만 제외. (예: "공무원 겸직" 상황에 "상표권 침해" → 제외)
- 사건명이 짧아 판단이 어려우면 포함하는 쪽으로.
- 최대 15개, 관련 가능성 높은 순.

[출력] JSON 숫자 배열만. 예: [3, 1, 5] / 없으면 []
''';

    final response = await _callGemini(prompt);
    dlog('🤖 1차선별 응답: $response');
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .take(15)
          .toList();
    } catch (e) {
      dlog('❌ 1차선별 파싱 실패: $e');
      return [];
    }
  }

  /// 판례 전용 rerank — 판시사항을 읽고 사용자 상황과 관련된 것만 선별
  /// 각 판례마다 판단 이유를 먼저 쓰게 해서(추론 강제) 정확도를 높임
  Future<List<int>> rerankPrecedents(String userInput, List<String> candidates) async {
    if (candidates.isEmpty) return [];

    final prompt = '''
당신은 법률 전문가입니다. 사용자 상황에 참고가 될 판례만 정확히 골라야 합니다.

[사용자 상황]
"$userInput"

[판례 후보] (번호: 판시사항)
${candidates.join('\n')}

[작업 순서 — 반드시 이 순서로]
1단계. 사용자의 구체적 행위에서 "직접 발생하는 핵심 쟁점"을 모두 나열하세요. 관련 법이 여러 개면 쟁점도 여러 개입니다. 단, 행위와 직접 관련 없는 일반 의무론(품위유지, 성실의무 등)은 핵심이 아닙니다.
   예) "공무원이 유튜브로 수익" → 핵심: 겸직·영리업무 금지 위반. (품위유지·성실의무 일반론은 제외)
   예) "해외직구 전자제품을 중고로 판매" → 핵심: ①전파법상 적합성평가(형식승인) 위반 ②전기용품 안전인증 위반. (둘 다 핵심)
   예) "익명 채팅앱 운영" → 핵심: ①음란물·불법정보 유통 책임 ②정보통신서비스 제공자의 관리의무.
2단계. 각 판례 후보마다 한 줄씩 두 가지를 판정:
   (a) 이 판례의 쟁점이 1단계 핵심 쟁점 중 하나에 해당하는가
   (b) 이 판례 속 행위가 사용자의 행위와 같은 종류인가 — 표현이 달라도 본질이 같으면 같은 종류입니다.
   예) 사용자 "인증 안 받은 제품 판매": "형식승인 없이 수입·판매" 판례 → (b)O (본질이 같음) / "법률의 위헌 여부"만 다툰 판례 → (b)X
   예) 사용자 "공무원 유튜브 수익": "여관 임대(부업)" 판례 → (b)O / "성비위 품위손상" → (b)X
3단계. (a)와 (b)를 모두 만족하는 판례를 전부, 관련도 순으로 선택. 일반 의무론만 다루는 판례는 제외.
   ★다양성: 거의 같은 쟁점을 다루는 판례가 여러 개면 가장 대표적인 1~2개만 남기세요. 서로 다른 쟁점이 고루 포함되는 것이 같은 쟁점 5개보다 사용자에게 유용합니다.
   예) "채팅앱 운영" 상황에서 명예훼손 성립요건 판례가 8개 통과됐다면 → 대표 1~2개만 남기고, 대신 운영자 방조책임·음란물 기준·개인정보 등 다른 쟁점 판례를 포함.

[판단 원칙]
- 핵심 쟁점과 무관한 "일반 의무"(품위유지, 성실의무 등) 판례를 끼워넣지 마세요.
- 애매하면 "그 판례를 읽는 게 사용자의 핵심 질문에 실제 도움이 되는가"로 판단.
- 관련된 게 여러 개면 모두, 없으면 빈 배열.

[출력 형식 — 정확히 이 JSON 구조로만]
{"analysis": "1단계: ... 2단계: 0번-..., 1번-..., ...", "selected": [번호들]}
예: {"analysis": "1단계: ①... 2단계: 0번-음란물 기준을 다룸, ①해당. 1번-의료법 쟁점, 무관. ...", "selected": [0, 3]}
''';

    final response = await _callGemini(prompt);
    dlog('🤖 rerank 응답: $response');
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      final List<dynamic> selected = parsed['selected'] as List<dynamic>? ?? [];
      return selected
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    } catch (e) {
      dlog('❌ rerank 파싱 실패: $e');
      return [];
    }
  }

  /// 검색된 법령/판례를 근거로 1~2문장 조언 생성
  Future<String> generateAdvice(
      String userInput,
      List<String> lawNames,
      List<String> precedentSummaries,
      ) async {
    final lawText = lawNames.isEmpty ? '없음' : lawNames.join(', ');
    final precText = precedentSummaries.isEmpty
        ? '없음'
        : precedentSummaries.take(2).join(' / ');

    final prompt = '''
사용자의 상황과 관련 법령·판례를 보고, 핵심 주의사항을 1~2문장으로 알려주세요.

[사용자 상황]
"$userInput"

[관련 법령]
$lawText

[관련 판례 요지]
$precText

[규칙]
- 반드시 1~2문장.
- "불법이다"라고 단정하지 말고 "~를 확인/주의해야 한다" 형태로 작성.
- 제공된 법령·판례 범위 안에서만 말하고, 없는 내용을 지어내지 마세요.
- 마지막에 전문가 상담 권유는 하지 마세요(앱이 따로 안내함).
- 순수 텍스트만 반환.
''';

    try {
      final response = await _callGemini(prompt);
      return response.trim();
    } catch (_) {
      return '';
    }
  }

  /// 법령 여러 개를 한 번에 요약 → "왜 만든 법인지"
  /// items: [{name, content}], 반환: index → 요약문
  /// 법령 여러 개를 한 번에 요약 → summary("무엇을 위한 법") + relevance("내 상황에서의 요점")
  /// 반환: index → {'summary': ..., 'relevance': ...}
  Future<Map<int, Map<String, String>>> batchSummarizeLaws(
      String userInput, List<Map<String, String>> items) async {
    if (items.isEmpty) return {};

    final sb = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      sb.writeln('[$i] ${items[i]['name']}: ${items[i]['content']}');
    }

    final prompt = '''
사용자의 상황과 관련 법령들이 있습니다. 각 법령에 대해 두 가지를 작성하세요.

[사용자 상황]
"$userInput"

[법령 목록]
${sb.toString()}

[작성할 것]
1. summary: 이 법이 무엇을 위한 법인지 일반인이 이해하기 쉽게 한 문장.
2. relevance: 사용자 상황에서 이 법의 요점이 무엇인지 한 문장. 이 법의 어떤 내용이 사용자 상황에 적용되는지 구체적으로.
   예) 상황이 "공무원인데 유튜브 수익", 법령이 "국가공무원법"이면
   → relevance: "공무원의 영리 업무와 겸직을 금지하는 내용이 있어, 유튜브 수익 활동 전 소속 기관의 허가가 필요합니다."
3. related: 제공된 법령 조문 내용이 사용자 상황과 실제로 관련 있으면 true, 엉뚱한 조문(예: 임대차 분쟁인데 미성년자 조항)이면 false.

[출력 형식] - JSON 객체만 반환. key는 번호(문자열), value는 {"summary": "...", "relevance": "...", "related": true}
예: {"0": {"summary": "...", "relevance": "...", "related": true}, "1": {"summary": "...", "relevance": "...", "related": false}}
★반드시 0번부터 ${items.length - 1}번까지 총 ${items.length}개 항목 전부에 대해 빠짐없이 응답하세요. 일부만 응답하면 안 됩니다.

[규칙]
- 각 문장은 쉽고 구체적으로.
- 제공된 법령 내용 범위 안에서만 작성. 내용에 없는 조항을 지어내지 마세요.
- relevance는 모든 항목에 반드시 작성하세요. 빈 문자열 금지. 법령 내용이 목적조뿐이라 구체적 연결이 어려우면, 이 법의 목적이 사용자 상황과 어떻게 닿는지라도 작성하세요.
- JSON만 반환, 다른 텍스트 없이.
''';

    final response = await _callGemini(prompt);
    dlog('🤖 법령요약 응답 (요청 ${items.length}개): $response');
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      final result = <int, Map<String, String>>{};
      parsed.forEach((key, value) {
        final idx = int.tryParse(key);
        if (idx != null && value is Map) {
          result[idx] = {
            'summary': value['summary']?.toString() ?? '',
            'relevance': value['relevance']?.toString() ?? '',
            'related': value['related']?.toString() ?? 'true',
          };
        }
      });
      // Gemini가 키를 1부터 시작한 경우 자동 보정 (0이 없고 항목 수가 맞으면 -1 shift)
      if (!result.containsKey(0) &&
          result.containsKey(1) &&
          result.length == items.length) {
        dlog('⚠️ 법령요약 인덱스 1-base 감지, 보정함');
        final shifted = <int, Map<String, String>>{};
        result.forEach((k, v) => shifted[k - 1] = v);
        return shifted;
      }
      return result;
    } catch (e) {
      dlog('❌ 법령요약 파싱 실패: $e');
      return {};
    }
  }

  /// 판례 여러 개를 한 번에 요약 → "어떤 이유로 재판이 열렸는지"
  /// items: [{caseNo, content}], 반환: index → 요약문
  Future<Map<int, String>> batchSummarizePrecedents(List<Map<String, String>> items) async {
    if (items.isEmpty) return {};

    final sb = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final content = items[i]['content'] ?? '';
      final trimmed = content.length > 600 ? content.substring(0, 600) : content;
      sb.writeln('[$i] ${items[i]['caseNo']}: $trimmed');
    }

    final prompt = '''
아래 판례들을 각각 "어떤 이유로(어떤 행위로) 이 재판이 열렸는지" 일반인이 이해하기 쉽게 한 문장으로 요약하세요.

[판례 목록]
${sb.toString()}

[출력 형식] - JSON 객체만 반환. key는 번호(문자열), value는 요약문.
예: {"0": "등록 없이 동물을 반복 판매한 행위로 기소된 사건입니다.", "1": "..."}

[규칙]
- 각 항목당 한 문장, 쉬운 표현.
- 법원 판단(결과)이 아니라 "왜 재판이 열렸는지"에 집중.
- JSON만 반환, 다른 텍스트 없이.
''';

    return _parseBatch(await _callGemini(prompt));
  }

  Map<int, String> _parseBatch(String response) {
    try {
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      final result = <int, String>{};
      parsed.forEach((k, v) {
        final idx = int.tryParse(k);
        if (idx != null) result[idx] = v.toString();
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 법령 상세 설명 생성 (일반인용)
  /// 반환: {what: 이 법이 뭐하는 법인지, forYou: 내 상황에서 봐야할 부분}
  Future<Map<String, String>> explainLaw(
      String userInput,
      String lawName,
      String articleContent,
      ) async {
    final prompt = '''
다음 법령을 법률 지식이 없는 일반인에게 설명하세요.

[사용자 상황]
"$userInput"

[법령명]
$lawName

[조문 내용]
$articleContent

[출력 형식] - 반드시 아래 JSON만 반환
{
  "what": "이 법이 무엇을 위한 법인지 쉬운 말로 1~2문장",
  "forYou": "사용자 상황에서 특히 주의하거나 확인해야 할 부분 1~2문장"
}

[규칙]
- 어려운 법률용어 대신 일상 표현 사용.
- 조문에 없는 내용을 지어내지 마세요.
- "불법이다" 단정 대신 "~를 확인해야 한다" 형태.
- JSON만 반환, 다른 텍스트 없이.
''';

    try {
      final response = await _callGemini(prompt);
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      return {
        'what': parsed['what']?.toString() ?? '',
        'forYou': parsed['forYou']?.toString() ?? '',
      };
    } catch (_) {
      return {'what': '', 'forYou': ''};
    }
  }

  /// 판례 상세 설명 생성 (일반인용)
  /// 반환: {result: 판결 결과 요약, background: 무슨 일로 재판이 열렸는지}
  Future<Map<String, String>> explainPrecedent(
      String caseName,
      String gistContent,
      ) async {
    // 너무 길면 앞부분만 (공소사실/주문이 앞쪽에 있음)
    final trimmed = gistContent.length > 2500
        ? gistContent.substring(0, 2500)
        : gistContent;

    final prompt = '''
다음 판례를 법률 지식이 없는 일반인에게 설명하세요.

[사건명]
$caseName

[판례 전문]
$trimmed

[출력 형식] - 반드시 아래 JSON만 반환
{
  "background": "무슨 일로 재판이 열렸는지(어떤 행위가 문제됐는지) 1~2문장",
  "result": "법원이 최종적으로 어떻게 판단했는지 결과 1~2문장"
}

[규칙]
- 어려운 법률용어 대신 일상 표현 사용.
- 제공된 내용에서만 작성, 지어내지 마세요.
- JSON만 반환, 다른 텍스트 없이.
''';

    try {
      final response = await _callGemini(prompt);
      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> parsed = jsonDecode(cleaned);
      return {
        'background': parsed['background']?.toString() ?? '',
        'result': parsed['result']?.toString() ?? '',
      };
    } catch (_) {
      return {'background': '', 'result': ''};
    }
  }

  /// Gemini API 공통 호출
  Future<String> _callGemini(String prompt) async {
    final url = Uri.parse('$_baseUrl?key=$_apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1, // 법률 관련이므로 낮게 설정
        'maxOutputTokens': 2000,
      }
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'] ?? '';
    } else if (response.statusCode == 429) {
      throw Exception('AI 요청 한도 초과입니다. 1분 후 다시 시도해주세요.');
    } else {
      throw Exception('Gemini API 오류: ${response.statusCode}');
    }
  }
}