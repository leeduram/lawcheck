import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/log.dart';

/// 인기 주제 카운트 (Firestore)
/// 컬렉션 구조: topics/{카테고리명} → { count: 숫자 }
class TrendingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'topics';

  /// 카테고리 카운트 +1 (없으면 생성)
  Future<void> increment(String category) async {
    try {
      final ref = _db.collection(_collection).doc(category);
      await ref.set({
        'count': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      dlog('❌ 인기주제 카운트 실패: $e');
      // 네트워크 실패 시 조용히 무시 (검색 기능엔 영향 없음)
    }
  }

  /// 인기 주제 TOP N 조회
  Future<List<TrendingTopic>> fetchTop({int limit = 10}) async {
    try {
      final snapshot = await _db
          .collection(_collection)
          .orderBy('count', descending: true)
          .limit(limit)
          .get();

      dlog('🔥 인기주제 로드: ${snapshot.docs.length}개');
      return snapshot.docs
          .map((d) => TrendingTopic(
        category: d.id,
        count: (d.data()['count'] ?? 0) as int,
      ))
          .toList();
    } catch (e) {
      dlog('❌ 인기주제 로드 실패: $e');
      return [];
    }
  }
}

class TrendingTopic {
  final String category;
  final int count;

  TrendingTopic({required this.category, required this.count});
}