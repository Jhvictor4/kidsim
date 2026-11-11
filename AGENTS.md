# AGENTS.md — KidSim 기획 현황과 작업 규칙

이 문서는 이 리포에서 일하는 에이전트(와 사람)를 위한 **현재 기획 스냅샷**입니다.
구조 요약은 `README.md`, Studio 수동 설정은 `SETUP.md`를 보세요. 여기에는 "무엇을
왜 이렇게 만들었는지", "지금 어디까지 왔는지", "다음에 뭘 고쳐야 하는지"를 적습니다.

마지막 갱신: 2026-11-11 (Linear AEO-1441) — 고정 사건+선택지 버튼 구조에서
**랜덤 고객 에이전트 + 멀티플레이 레인** 구조로 전환.

---

## 1. 한 줄 컨셉

**"Isaac Sim, but for kids."** 로봇이 시뮬레이터에서 먼저 연습하고 현실로 나가듯,
아이가 Roblox 안에서 실제 생활 기술(필요 파악, 제안, 정직한 가격, 협상, 고객 응대)을
연습하고, 마지막 **디브리프**에서 "방금 한 게 현실의 어디에 쓰이는지"를 확인합니다.

- 대상: 10–13세. 언어: 영어(현재).
- 출신: c0mpiled-18 YC Startup School 해커톤. 피치 프레임은 YC RFS "The $15-an-Hour Expert".
- 핵심 산출물: **90초 데모 영상** (thesis → 친구와 라운드 시작 → 랜덤 고객 설득 + 코치 힌트 → 결과/디브리프).

## 2. 게임 루프 (현재)

```
Lobby 카드 ("Start the round" — 누구나 눌러서 전원 시작)
  → 3초 카운트다운
  → 3분 라운드: 플레이어마다 자기 카운터 레인
       랜덤 고객이 걸어옴 → 고객이 먼저 말함 → 아이가 자유 채팅으로 응대/설득
       → 고객 에이전트가 매 턴 결정: 계속 대화 / 구매 / 떠남 + 별점
       → 서버가 구매를 검증해 매출·재고·점수 반영 → 다음 고객
       (Coach 버튼: 고객당 1회 힌트, 상단 리더보드 실시간)
  → Time's up → 결과: 순위, "지갑 속 $Y 중 $X를 벌었다(%)", 고객별 결과/별점, 디브리프
  → "Back to the lobby"
```

**점수 = 매출 + 행복 보너스** = `revenue + 2 × Σ(stars − 3)` (`Config.STARS_WEIGHT`).
강매로 1점을 받으면 $4 손해, 5점이면 $4 이득. 레인의 평균 별점은 **다음 고객 지갑 크기**에
반영됩니다(입소문, `BUZZ_*`, ×0.7–1.3). "지갑에서 최대한 뽑아내기"가 목표지만
착취는 손해가 되도록 설계한 것이 핵심입니다(사용자 결정: 매출+만족도).

## 3. 설계 원칙 (바꾸기 전에 합의할 것)

1. **LLM은 제안, 서버가 결정.** 고객 에이전트는 JSON(`say`, `decision`, `items`, `pay`, `stars`)으로
   답하고, `LaneEngine.settle`이 이를 검증합니다:
   - 메뉴에 있는 품목만(키/라벨을 대소문자·공백·복수형 무시하고 매칭), 재고 한도 내.
   - **메뉴가보다 비싸게 받을 수 없음**(바가지 불가). 아이가 제안한 할인은 허용.
   - 합의 금액이 지갑을 넘으면 비싼 품목부터 빼서 맞춤.
   - 합의가보다 낮게 정산되면 `[KidSim] Sale settled below the agreed price` 경고.
2. **지갑·취향·가격 성향은 숨김.** 클라이언트에는 이름/나이대/상황만 갑니다(`CustomerGen.visible`).
   아이는 대화로 알아내야 하고, 고객은 물어보면 힌트를 줄 수 있습니다.
3. **실패해도 라운드는 끝난다.** LLM 호출 실패 시 고객은 시간을 끌다 인내심이 다하면 떠납니다.
   평가 실패 시 결정적 폴백 디브리프.
4. **엔진은 팩을 모른다.** `RoundManager`/`LaneEngine`/`CustomerGen`/`AgentRuntime`에 카페 개념 없음.
   새 시나리오 = `src/server/Packs/`에 메뉴·재고·고객 범위·프롬프트를 담은 모듈 하나. 계약은 `src/shared/Types.luau`.
5. **월드도 코드다.** `WorldBuilder`가 N개 레인(카운터, 칸막이, 실시간 점수 간판)을 생성. `.rbxlx`는 빌드 산출물.
6. **키는 서버에만.** LLM 호출은 전부 서버 `HttpService`.

## 4. 모듈 지도

| 파일 | 역할 |
|---|---|
| `server/Main.server.luau` | 리모트 생성, 월드 빌드, `RoundManager.start` |
| `server/RoundManager.luau` | lobby/countdown/running/closing/results, 레인 배정, 리더보드, 병렬 평가 |
| `server/LaneEngine.luau` | 플레이어 1명 × 라운드 1회: 고객 루프, 대화, 판매 검증, 기록 |
| `server/CustomerGen.luau` | 팩 범위에서 랜덤 고객 생성(입소문 배율 적용) |
| `server/AgentRuntime.luau` | 고객/코치/평가자 프롬프트 + JSON 파싱 |
| `server/LlmClient.luau` | OpenAI 호환 호출, `jsonMode`(400이면 자동 해제) |
| `server/Config.luau` | 라운드 길이, 레인 수, 점수 가중치, 입소문, 토큰 예산 |
| `server/Packs/CafeShift.luau` | 메뉴 6종, 재고, 고객 이름/나이대 예산/상황/취향/성향, 프롬프트 |
| `client/Main.client.luau` | 로비, HUD, 리더보드, 대화 로그, 코치, 결과/디브리프 |

리모트: S→C `Phase, State, Customer, Dialogue, CoachHint, Debrief, Toast, Busy, Leaderboard, Timer` /
C→S `Say, RequestHint, StartRound, Continue`.

## 5. Cafe Shift 팩 수치

- 메뉴: Coffee $4 · Hot Chocolate $3 · Lemonade $3 · Sandwich $6 · Croissant $3 · Cookie $2.
- 재고(플레이어별·라운드별): 12 / 10 / 10 / 6 / 8 / 15.
- 나이대 예산: kid $2–8, teen $5–14, adult $8–30, senior $6–20 (가중치 2/3/4/2).
- 인내심: 아이 발화 3–6회 후 결정. 무응답 35초면 떠남(2점).
- 라운드 180초, 최대 4레인.

## 6. 현재 상태 (2026-11-11)

- 비공개 게시: "KidSim - Cafe Shift" (placeId 78858397239070), Allow HTTP Requests On.
- 개발 키: `DevSecrets.luau`(OpenAI 호환). 기본 Config는 GMI Cloud.
- Studio MCP 1인 실측(새 구조): 3분에 고객 3명 응대, **$14 / 평균 4.7★ / 24점, 지갑 $59 중 24%**.
  고객 대사·예산 제약("I can only spend $4")·가격 협상·코치 힌트·평가 JSON 모두 실제 LLM 응답.
  스크린샷: `demo/agentic-*.jpg`.
- 실측에서 잡은 버그와 수정:
  - 지갑 상한을 메뉴가 기준으로 걸어서, 할인 딜($5어치를 $4에)이 품목 삭제로 바뀌던 문제 → 합의 금액 기준으로 수정.
  - 고객이 `items`를 빠뜨리거나 키를 다르게 쓰는 경우 → 느슨한 키 매칭 + 프롬프트 강화 + 경고 로그.
  - `settle` 단위 테스트 6케이스(할인, 느슨한 키, 바가지 시도, 지갑 부족, 모르는 품목, 재고 한도) 통과.
- **2인 멀티플레이는 아직 실제로 검증하지 못함**(Studio MCP는 1인 Play만 가능). Studio의
  Test → Clients and Servers(2명)로 확인 필요.

## 7. 알려진 공백 / 다음 과제

1. **2인 실검증.** 레인 배정, 리더보드 동기화, 중간 입장(waiting 배너), 퇴장 시 레인 해제.
2. **LLM이 `items`를 빠뜨리는 문제**는 프롬프트로 줄였을 뿐 근본 해결이 아님. 경고 로그 빈도를 보고,
   필요하면 "구매 확인" 단계(서버가 장바구니를 요약해 고객에게 한 번 더 확인)를 추가.
3. **응답 대기 시간.** 매 턴 LLM 1회라 3분에 고객 3명 정도. 데모용으로는 라운드 90–120초 또는 짧은 인내심 고려.
4. **카메라/월드.** 플레이어 캐릭터가 화면 하단을 가림. 라운드 중 고정 카메라(카운터 너머 고객 정면)가 데모에 유리.
5. **간판 겹침.** 비스듬한 각도에서 레인 BillboardGui 제목이 겹쳐 보임.
6. **연령 적합성 점검.** 고객 프롬프트는 가드레일이 있지만, 아이의 입력에 대한 모더레이션(Roblox TextService 필터링)은 아직 없음.
   공개 전 `TextService:FilterStringAsync` 적용 필요.

## 8. 에이전트 작업 규칙

- **`src/server/DevSecrets.luau`는 절대 커밋/출력 금지.** (gitignore됨) 로컬 HTTP 서버로 `src/`를 서빙하지 말 것(이 파일이 포함됨).
- 빌드: `rojo build -o kidsim.rbxlx`. Studio에서 MCP로 스크립트를 고쳤다면 같은 변경을 `src/`에도
  반영하고, 길이+해시 비교로 동기화를 확인할 것(반대도 마찬가지).
- Studio 에디트 모드의 `execute_luau`는 Assistant HTTP allowlist 때문에 localhost를 못 부르고, 서버 컨텍스트
  `execute_luau`에서 직접 LLM을 부르면 "Assistant HTTP permissions are not configured"로 실패함(게임 자체 호출은 정상).
  스크립트 동기화는 `execute_luau`로 Source 직접 설정 또는 `multi_edit`.
- **UI 레이아웃:** 새 `UIListLayout`은 반드시 `SortOrder = Enum.SortOrder.LayoutOrder`(클라이언트의 `list()` 헬퍼 사용).
  기본값(Name)은 같은 클래스 이름 형제들의 순서를 뒤섞음.
- **Studio MCP로 플레이 테스트할 때:**
  - 주요 위젯은 고정 이름이 있음: `KidSimUI.LobbyOverlay.LobbyCard.StartButton`,
    `KidSimUI.Bottom.ChatRow.{ChatBox,ReplyButton,CoachButton}`, `KidSimUI.Bottom.Talk.{Log,CustomerTitle,Typing}`,
    `KidSimUI.DebriefOverlay.DebriefCard`.
  - 채팅: ChatBox 클릭 → `textInput`(별도 호출, instance_path 지정) → ReplyButton 클릭.
  - 마우스 좌표를 쓸 땐 스크린샷 픽셀이 아니라 GUI `AbsolutePosition` 좌표계.
  - LLM 이상 여부는 `get_console_output`에서 `[KidSim] LLM call failed` / `Evaluator fell back` /
    `Sale settled below the agreed price` / `unknown item` 확인.
- 팩 수치·점수식을 바꾸면 §2, §5와 README를 같이 갱신할 것.
