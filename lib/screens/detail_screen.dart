import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/law_result.dart';
import '../models/precedent_result.dart';
import '../services/legal_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';

class DetailScreen extends StatefulWidget {
  final LawResult? law;
  final PrecedentResult? precedent;
  final String userInput; // 사용자 원래 질문 (법령 설명 맥락용)

  const DetailScreen.law({
    super.key,
    required LawResult this.law,
    this.userInput = '',
  }) : precedent = null;

  const DetailScreen.precedent({
    super.key,
    required PrecedentResult this.precedent,
    this.userInput = '',
  }) : law = null;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final LegalService _legalService = LegalService();
  final GeminiService _gemini = GeminiService();

  String? _fullText;
  Map<String, String> _explanation = {};
  bool _loading = true;

  bool get _isLaw => widget.law != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_isLaw) {
      final law = widget.law!;
      // 법령 전문 + AI 설명 병렬
      final results = await Future.wait([
        _legalService.fetchFullLaw(law.lawId),
        _gemini.explainLaw(widget.userInput, law.lawName, law.summary),
      ]);
      if (!mounted) return;
      setState(() {
        _fullText = results[0] as String;
        _explanation = results[1] as Map<String, String>;
        _loading = false;
      });
    } else {
      final prec = widget.precedent!;
      final exp = await _gemini.explainPrecedent(
        prec.caseNo,
        prec.fullContent.isNotEmpty ? prec.fullContent : prec.summary,
      );
      if (!mounted) return;
      setState(() {
        _explanation = exp;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
          color: AppTheme.textPrimary,
        ),
        title: Text(
          _isLaw ? widget.law!.lawName : widget.precedent!.caseNo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('AI가 쉽게 설명하고 있습니다...',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            ],
          ),
        )
            : _isLaw
            ? _buildLawDetail()
            : _buildPrecedentDetail(),
      ),
    );
  }

  // 전문 초반 일부만 (약 600자)
  String _previewText(String full) {
    if (full.length <= 600) return full;
    return full.substring(0, 600).trim();
  }

  // 설명 박스 공통 위젯
  Widget _explainBox(String label, String content, IconData icon, Color color) {
    if (content.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(content,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildLawDetail() {
    final law = widget.law!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 법령명 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(law.lawName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                if (law.articleNo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('제${law.articleNo}조 ${law.articleTitle}',
                      style: const TextStyle(fontSize: 14, color: AppTheme.primary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI 쉬운 설명
          _explainBox('이런 법이에요', _explanation['what'] ?? '',
              Icons.menu_book_outlined, AppTheme.primary),
          _explainBox('내 상황에서는', _explanation['forYou'] ?? '',
              Icons.person_pin_circle_outlined, AppTheme.accent),

          const SizedBox(height: 12),

          // 법령 전문 (제목 + 전문 보기 버튼)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('법령 전문',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(
                    'https://www.law.go.kr/DRF/lawService.do?OC=duram&target=law&ID=${law.lawId}&type=HTML',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Text('전문 보기',
                          style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 2),
                      Icon(Icons.open_in_new, size: 13, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _previewText(_fullText ?? ''),
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.8),
                ),
                if ((_fullText ?? '').length > 600) ...[
                  const SizedBox(height: 8),
                  Text('... (전문 보기에서 전체 확인)',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withOpacity(0.7))),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text('출처: 국가법령정보센터 (open.law.go.kr) | 공공누리 1유형',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildPrecedentDetail() {
    final prec = widget.precedent!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 판례 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prec.caseNo,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                const SizedBox(height: 6),
                Text('${prec.courtName}  ·  ${prec.judgDate}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.accent)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI 쉬운 설명
          _explainBox('어떤 사건이었나요', _explanation['background'] ?? '',
              Icons.help_outline, AppTheme.primary),
          _explainBox('법원의 판단', _explanation['result'] ?? '',
              Icons.gavel_outlined, AppTheme.accent),

          const SizedBox(height: 12),

          // 대법원 전문 링크
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(prec.detailUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('판례 전문 보기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('출처: 국가법령정보센터 (open.law.go.kr) | 공공누리 1유형',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withOpacity(0.6))),
        ],
      ),
    );
  }
}