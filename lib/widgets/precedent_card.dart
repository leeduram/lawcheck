import 'package:flutter/material.dart';
import '../models/precedent_result.dart';
import '../theme/app_theme.dart';

class PrecedentCard extends StatelessWidget {
  final PrecedentResult precedent;
  final VoidCallback onTap;

  const PrecedentCard({super.key, required this.precedent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 판례 태그 + 사건번호
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '판례',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      precedent.caseNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 법원명 + 선고일
              Row(
                children: [
                  Icon(Icons.account_balance, size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${precedent.courtName}  ·  ${precedent.judgDate}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // AI 요약
              Text(
                precedent.summary,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // 상세보기 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '판례 전문 보기',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accent.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.open_in_new,
                    size: 12,
                    color: AppTheme.accent.withOpacity(0.9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}