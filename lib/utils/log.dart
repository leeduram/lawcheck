import 'package:flutter/foundation.dart';

/// 디버그 빌드에서만 출력되는 로그.
/// 출시(release) 빌드에서는 컴파일 단계에서 제거되어 아무것도 출력하지 않음.
void dlog(Object? message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}
