# LawCheck (법률 리스크 확인 앱)

"내가 하려는 일"을 문장으로 입력하면, 관련 법령과 판례를 찾아 쉬운 말로 요약해 주는 Android 앱입니다.

(개발 기간 2026.05.25 ~ 06.13)

## 동작 구조

```
[검색어 생성] → [넓게 검색] → [2단계 선별] → [재검색] → [요약·조언]
  Gemini         공공 API       Gemini         공공 API     Gemini
```

1. Gemini가 입력 문장에서 법령 검색어와 판례 검색어를 만듭니다.
2. 국가법령정보 Open API로 법령과 판례 후보를 넓게 모읍니다.
3. 사건명으로 1차 선별(최대 15건)하고, 판시사항을 읽어 2차로 다시 고릅니다.
4. 결과가 좋았던 검색어만 더 깊게 다시 검색해 빠진 판례를 찾습니다.
5. 법령과 판례를 쉬운 말로 요약하고, 내 상황에서의 요점과 조언을 보여 줍니다.

**판례와 법령 내용은 AI가 만들지 않고 공공 API에서만 가져옵니다.** 관련 판례가 없으면 억지로 채우지 않고 0건으로 표시합니다.

## 화면

- 입력 화면: 자유 입력, 인기 주제 TOP 10, 검색 기록
- 결과 화면: AI 요약, 법령 카드, 판례 카드
- 상세 화면: 선택한 법령·판례 설명, 국가법령정보 원문 링크

## 사용 기술

- Flutter (Dart), Android Studio
- Gemini API
- 국가법령정보 Open API (REST / XML)
- Firebase Firestore (인기 주제 집계), SharedPreferences (검색 기록)

## 폴더

| 경로 | 내용 |
|---|---|
| `lib/screens/` | 입력, 결과, 상세, 시작 화면 |
| `lib/services/gemini_service.dart` | 검색어 생성, 선별, 요약, 조언 |
| `lib/services/legal_service.dart` | 법령·판례 검색과 조문 선택 |
| `lib/services/trending_service.dart` | 인기 주제 집계 |
| `lib/services/history_service.dart` | 검색 기록 저장 |

## 실행 방법

1. `lib/services/secrets.example.dart`를 `secrets.dart`로 복사하고 자신의 Gemini API 키와 국가법령정보 Open API 아이디를 넣습니다.
2. `flutter pub get` 후 실행합니다.

분석 결과는 참고용이며 법적 효력이 없습니다. 법령 데이터 출처: 국가법령정보센터(공공누리 1유형).

기능은 직접 기획하고 AI 코딩 도구를 활용해 구현했습니다.
