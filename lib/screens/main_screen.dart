import 'package:flutter/material.dart';
import '../utils/log.dart';
import 'package:flutter/services.dart';
import '../models/history_item.dart';
import '../models/law_result.dart';
import '../models/precedent_result.dart';
import '../services/gemini_service.dart';
import '../services/history_service.dart';
import '../services/legal_service.dart';
import '../services/category_classifier.dart';
import '../services/trending_service.dart';
import '../theme/app_theme.dart';
import '../widgets/drawer_widget.dart';
import 'result_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final GeminiService _gemini = GeminiService();
  final LegalService _legalService = LegalService();
  final HistoryService _historyService = HistoryService();
  final TrendingService _trending = TrendingService();

  bool _isLoading = false;
  String _loadingMessage = '';
  List<TrendingTopic> _trendingTopics = [];

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    final topics = await _trending.fetchTop(limit: 10);
    if (mounted) setState(() => _trendingTopics = topics);
  }

  Future<void> _analyze() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _loadingMessage = 'AI가 키워드를 분석하고 있습니다...';
    });

    try {
      // 1. Gemini로 법령 + 판례 키워드 한 번에 생성
      final keywords = await _gemini.extractKeywords(query);
      final lawKeywords = keywords['law'] ?? [];
      // 조문 검색용 쟁점 키워드 (없으면 법령 키워드로 대체)
      final articleKeywords = (keywords['article'] ?? []).isNotEmpty
          ? keywords['article']!
          : lawKeywords;
      final precedentKeywords = keywords['precedent'] ?? [];

      // 키워드로 카테고리 분류 후 인기 주제 카운트 (AI 호출 없음, 비동기)
      final category = CategoryClassifier.classify(lawKeywords);
      _trending.increment(category); // await 안 함 - 백그라운드 처리

      setState(() => _loadingMessage = '관련 법령을 검색하고 있습니다...');

      // 2. 법령 후보 넓게 수집 (법령명만)
      final candidates = await _legalService.fetchLawCandidates(lawKeywords);

      // 3. Gemini가 관련있는 법령만 골라냄 (rerank)
      List<Map<String, String>> confirmedLaws = candidates;
      if (candidates.isNotEmpty) {
        setState(() => _loadingMessage = '관련도를 분석하고 있습니다...');
        final candidateLabels = List.generate(
          candidates.length,
              (i) => '$i: ${candidates[i]['lawName']}',
        );
        final picked = await _gemini.rerank(query, candidateLabels);
        if (picked.isNotEmpty) {
          confirmedLaws = picked
              .where((i) => i >= 0 && i < candidates.length)
              .map((i) => candidates[i])
              .take(5)
              .toList();
        } else {
          confirmedLaws = candidates.take(5).toList();
        }
      }

      setState(() => _loadingMessage = '법령 상세와 판례를 불러오는 중...');

      // 4. 판례 검색 쿼리 — Gemini가 만든 의미 있는 2단어 조합을 그대로 사용
      final kws = precedentKeywords.take(8).toList();
      final qSeen = <String>{};
      final dedupQueries = kws.where((q) => qSeen.add(q.trim())).toList();

      // [1단계] 법령 상세 + 판례 사건명 수집 (병렬, 상세조회 없어 빠름)
      final results = await Future.wait([
        _legalService.fetchLawDetails(confirmedLaws, articleKeywords),
        _legalService.collectPrecedentCandidates(dedupQueries),
      ]);

      final laws = results[0] as List<LawResult>;
      final precCandidates = results[1] as List<Map<String, String>>;
      var precedents = <PrecedentResult>[];

      dlog('📋 후보 풀: ${precCandidates.length}개');

      // [2단계] 1차 선별 — 사건명만 보고 관련 가능성 있는 것 거르기 (Gemini)
      var picked1st = <Map<String, String>>[];
      if (precCandidates.isNotEmpty) {
        final caseNameLabels = List.generate(
          precCandidates.length,
              (i) => '$i: ${precCandidates[i]['caseName']}',
        );
        try {
          final indices = await _gemini.prefilterPrecedents(query, caseNameLabels);
          picked1st = indices
              .where((i) => i >= 0 && i < precCandidates.length)
              .map((i) => precCandidates[i])
              .toList();
        } catch (_) {
          picked1st = precCandidates.take(10).toList();
        }
      }
      dlog('📋 1차 선별: ${picked1st.length}개');

      // [3단계] 1차 통과한 것만 상세조회 (판시사항+본문)
      final detailedPrecedents =
      await _legalService.fetchPrecedentDetails(picked1st);
      dlog('📋 상세조회 통과: ${detailedPrecedents.length}개');
      for (final p in detailedPrecedents) {
        dlog('   후보: [${p.caseNo}] ${p.summary.length > 60 ? p.summary.substring(0, 60) : p.summary}');
      }

      // [4단계] 2차 rerank — 판시사항으로 정밀 선별 (무관하면 0건)
      var rerankedPrecedents = <PrecedentResult>[];
      if (detailedPrecedents.isNotEmpty) {
        final precLabels = List.generate(
          detailedPrecedents.length,
              (i) => '$i: [${detailedPrecedents[i].caseNo}] ${detailedPrecedents[i].summary}',
        );
        try {
          final picked = await _gemini.rerankPrecedents(query, precLabels);
          rerankedPrecedents = picked
              .where((i) => i >= 0 && i < detailedPrecedents.length)
              .map((i) => detailedPrecedents[i])
              .toList();
        } catch (_) {
          rerankedPrecedents = detailedPrecedents.take(3).toList();
        }
      }

      // [2회전] 1회전에서 정답을 낸 "검증된 쿼리"만 깊게 재검색
      if (rerankedPrecedents.isNotEmpty) {
        // 살아남은 판례들의 출신 쿼리 역추적 (한 판례가 여러 쿼리에서 나왔으면 전부)
        final survivorCaseNos = rerankedPrecedents.map((p) => p.caseNo).toSet();
        final provenQueries = precCandidates
            .where((c) => survivorCaseNos.contains(c['caseNo']))
            .expand((c) => (c['sourceQuery'] ?? '').split('||'))
            .where((q) => q.trim().isNotEmpty)
            .toSet()
            .toList();
        dlog('🎯 검증된 쿼리: $provenQueries');

        if (provenQueries.isNotEmpty) {
          // 깊은 재검색 (이미 본 후보 전체 제외)
          final allSeenCaseNos =
          precCandidates.map((c) => c['caseNo'] ?? '').toSet();
          final deepCandidates = await _legalService.deepCollectCandidates(
              provenQueries, allSeenCaseNos);
          dlog('📋 [2회전] 새 후보 풀: ${deepCandidates.length}개');

          if (deepCandidates.isNotEmpty) {
            // 1차 선별
            var deepPicked = <Map<String, String>>[];
            final deepLabels = List.generate(
              deepCandidates.length,
                  (i) => '$i: ${deepCandidates[i]['caseName']}',
            );
            try {
              final indices =
              await _gemini.prefilterPrecedents(query, deepLabels);
              deepPicked = indices
                  .where((i) => i >= 0 && i < deepCandidates.length)
                  .map((i) => deepCandidates[i])
                  .toList();
            } catch (_) {}
            dlog('📋 [2회전] 1차 선별: ${deepPicked.length}개');

            if (deepPicked.isNotEmpty) {
              // 상세조회 + 2차 rerank
              final deepDetailed =
              await _legalService.fetchPrecedentDetails(deepPicked);
              dlog('📋 [2회전] 상세조회 통과: ${deepDetailed.length}개');
              for (final p in deepDetailed) {
                dlog('   [2회전] 후보: [${p.caseNo}] ${p.summary.length > 60 ? p.summary.substring(0, 60) : p.summary}');
              }
              if (deepDetailed.isNotEmpty) {
                final deepPrecLabels = List.generate(
                  deepDetailed.length,
                      (i) => '$i: [${deepDetailed[i].caseNo}] ${deepDetailed[i].summary}',
                );
                try {
                  final picked2 =
                  await _gemini.rerankPrecedents(query, deepPrecLabels);
                  final deepReranked = picked2
                      .where((i) => i >= 0 && i < deepDetailed.length)
                      .map((i) => deepDetailed[i])
                      .toList();
                  dlog('📋 [2회전] rerank 후: ${deepReranked.length}개');
                  // 1회전 결과 뒤에 병합 (중복 없음 — 이미 제외했음)
                  rerankedPrecedents = [...rerankedPrecedents, ...deepReranked];
                } catch (_) {}
              }
            }
          }
        }
      }

      // 최대 5개 (관련된 것만)
      precedents = rerankedPrecedents.take(5).toList();
      dlog('📋 rerank 후: ${precedents.length}개');

      // 6. 미리보기 배치 요약 (법령: 무슨법+내상황요점 / 판례: 왜 재판 열림)
      setState(() => _loadingMessage = '결과를 쉽게 정리하는 중...');
      var summarizedLaws = laws;
      var summarizedPrecedents = precedents;
      try {
        final lawFuture = _gemini.batchSummarizeLaws(
          query,
          laws.map((l) => {'name': l.lawName, 'content': l.summary}).toList(),
        );
        final precFuture = _gemini.batchSummarizePrecedents(
          precedents.map((p) => {'caseNo': p.caseNo, 'content': p.fullContent}).toList(),
        );
        final lawSummaries = await lawFuture;
        final precSummaries = await precFuture;

        summarizedLaws = List.generate(laws.length, (i) {
          final s = lawSummaries[i];
          if (s == null) return laws[i];
          return laws[i].copyWith(
            previewSummary: (s['summary'] ?? '').isNotEmpty ? s['summary'] : null,
            relevance: (s['relevance'] ?? '').isNotEmpty ? s['relevance'] : null,
          );
        });
        // 무관 판정(related=false)된 법령은 제외 (엉뚱한 조문 안전망)
        final relatedFlags = List.generate(
            laws.length, (i) => lawSummaries[i]?['related'] != 'false');
        final filtered = <LawResult>[];
        for (var i = 0; i < summarizedLaws.length; i++) {
          if (relatedFlags[i]) {
            filtered.add(summarizedLaws[i]);
          } else {
            dlog('🚫 무관 법령 제외: ${summarizedLaws[i].lawName} 제${summarizedLaws[i].articleNo}조');
          }
        }
        if (filtered.isNotEmpty) summarizedLaws = filtered;
        summarizedPrecedents = List.generate(precedents.length, (i) {
          final s = precSummaries[i];
          return (s != null && s.isNotEmpty) ? precedents[i].copyWith(summary: s) : precedents[i];
        });
      } catch (_) {}

      final finalLaws = summarizedLaws;
      final finalPrecedents = summarizedPrecedents;

      // 7. Gemini 조언 생성 (검색 결과 기반)
      String advice = '';
      if (finalLaws.isNotEmpty || finalPrecedents.isNotEmpty) {
        setState(() => _loadingMessage = '핵심 주의사항을 정리하는 중...');
        advice = await _gemini.generateAdvice(
          query,
          finalLaws.map((l) => l.lawName).toList(),
          finalPrecedents.map((p) => p.summary).toList(),
        );
      }

      // 8. 히스토리 저장
      final historyItem = HistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        query: query,
        advice: advice,
        createdAt: DateTime.now(),
        laws: finalLaws,
        precedents: finalPrecedents,
      );
      await _historyService.save(historyItem);

      if (!mounted) return;

      // 9. 결과 화면으로 이동 (돌아오면 인기 주제 갱신)
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            query: query,
            advice: advice,
            laws: finalLaws,
            precedents: finalPrecedents,
          ),
        ),
      );
      _loadTrending();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류가 발생했습니다: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onHistorySelect(HistoryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          query: item.query,
          advice: item.advice,
          laws: item.laws,
          precedents: item.precedents,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 메인에서 뒤로가기 → 종료 확인
  Future<void> _onBackPressed() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('앱 종료', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('LawCheck를 종료하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('아니요', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('종료', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (exit == true) {
      SystemNavigator.pop(); // 앱 종료
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.surface,
      drawer: HistoryDrawer(onSelect: _onHistorySelect),
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          color: AppTheme.textPrimary,
        ),
        title: const Text('LawCheck'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _isLoading ? _buildLoading() : _buildMain(),
      ),
    );

    // 메인에서 시스템 뒤로가기 → 종료 확인 다이얼로그
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _onBackPressed();
      },
      child: scaffold,
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 20),
          Text(
            _loadingMessage,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 영역
            const Icon(Icons.balance, size: 52, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              '무엇을 하려고 하시나요?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '하려는 일을 입력하면 관련 법률과 판례를 찾아드립니다',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 입력 영역
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '예) 나는 치킨집을 창업하려고 해\n예) 유튜브로 수익을 내려고 해\n예) 아파트를 단기 임대하려고 해',
                hintStyle: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textPrimary,
                height: 1.6,
              ),
              onSubmitted: (_) => _analyze(),
            ),
            const SizedBox(height: 16),

            // 분석 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _analyze,
                icon: const Icon(Icons.search, size: 20),
                label: const Text('법률 리스크 분석하기'),
              ),
            ),
            const SizedBox(height: 20),

            // 면책 고지
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI 분석 결과는 참고용이며 법적 효력이 없습니다. 중요한 사항은 법률 전문가와 상담하세요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 인기 주제 TOP 10
            if (_trendingTopics.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  Icon(Icons.trending_up, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  const Text(
                    '많이 찾는 주제',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_trendingTopics.length, (i) {
                  final topic = _trendingTopics[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: i < 3 ? AppTheme.accent : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          topic.category,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}