# AGENTS.md — KidSim 기획 현황과 작업 규칙

이 문서는 이 리포에서 일하는 에이전트(와 사람)를 위한 **현재 기획 스냅샷**입니다.
구조 요약은 `README.md`, Studio 수동 설정은 `SETUP.md`를 보세요. 여기에는 "무엇을
왜 이렇게 만들었는지", "지금 어디까지 왔는지", "다음에 뭘 고쳐야 하는지"를 적습니다.

마지막 갱신: 2026-11-11 (Linear AEO-1441).
기획 변천: 고정 사건 + 선택지 버튼 → 아이가 직접 손님 설득(채팅) → **현재: 아이가 사장님,
직원 에이전트를 관리** (아이가 타이핑하는 건 말이 안 된다는 사용자 판단).

---

## 1. 한 줄 컨셉

**"Isaac Sim, but for kids."** 아이가 Roblox 안에서 **가게 사장님**이 되어, 숨겨진 성격을 가진
AI 직원들에게 규칙을 정해주고, 질문에 답하고, 증거를 보고 칭찬·경고·해고합니다. 마지막 디브리프에서
"직원들이 실제로 어떤 사람이었는지"와 "방금 연습한 기술이 현실의 어디에 쓰이는지"를 확인합니다.

- 대상: 10–13세. 언어: 영어(현재). **아이는 아무것도 타이핑하지 않음** — 전부 버튼/칩.
- 연습하는 기술: 분명한 규칙 정하기, 맡기기(delegation), 행동(증거)으로 사람 판단하기, 공정한 피드백,
  팀 질문에 빨리 답하기. 현실 전이: 조별 과제 리더, 팀 주장, 학급 행사, 동생 돌보기.
- 핵심 산출물: **90초 데모 영상** (README "The 90-second demo").

## 2. 게임 루프

```
Lobby ("Open the cafe" — 누구나 눌러서 서버 전원 시작)
  → 카운트다운 (직원 3명이 문으로 걸어 들어옴, 사장은 왕좌에 앉혀짐)
  → 3분 라운드, 플레이어마다 자기 가게:
       카운터 3개 × (직원 에이전트 ↔ 랜덤 손님 에이전트) 대화가 자동으로 진행
       말풍선 + TTS 음성 (사장 근처 대화만 소리, 사장에게 하는 질문은 항상 소리)
       직원이 애매하면 왕좌로 걸어와 질문 → 질문 카드 버튼 2~3개 + "You decide"
         (20초 안에 답 없으면 직원이 알아서 결정, "unanswered"로 기록)
       사장 도구: 규칙 칩(할인/판매 강도/먼저 물어볼 것), 직원 카드의 Praise/Warn/Fire
       해고 → 8초 후 새 랜덤 직원 입장(채용비 $5)
  → Closing → 결과: 리더보드, 가게 성적, "직원들의 진짜 성격" 공개, 평가(기술/잘한 점/주의/현실 전이/다음 드릴)
```

**점수 = 매출 − 채용비 + 2 × Σ(별점 − 3).** 가게 평균 별점이 다음 손님 지갑 크기에 반영(입소문).

## 3. 설계 원칙 (바꾸기 전에 합의할 것)

1. **LLM은 제안, 서버가 결정.** 손님 JSON(`say/decision/items/pay/stars/complaint`)과 직원 JSON
   (`say/action/question/options`)은 제안일 뿐. `ShopEngine.settle`이 메뉴가 초과 금지(할인은 허용),
   재고, 지갑을 검증하고, `ShopEngine.ruleBreaks`가 **현재 규칙 기준**으로 위반을 판정합니다
   (할인 상한 초과, "먼저 물어볼 것" 규칙을 어기고 할인).
2. **성격은 숨김.** 직원 성격 라벨은 디브리프 전까지 클라이언트에 안 감. 손님 지갑/취향도 숨김.
3. **실패해도 라운드는 끝난다.** LLM 실패 시 대사 폴백, TTS 실패 시 조용히 텍스트만(4회 연속 실패면 끔).
4. **엔진은 팩을 모른다.** `RoundManager`/`ShopEngine`/`CustomerGen`/`AgentRuntime`에 카페 개념 없음.
   새 업종 = `src/server/Packs/`에 메뉴·재고·손님 범위·직원 성격·규칙 옵션·프롬프트를 담은 모듈 하나.
   규칙 옵션의 기계 판정 필드: `maxDiscountPct`, `askAboveDiscountPct` (`src/shared/Types.luau`).
5. **월드도 코드다.** `WorldBuilder`가 가게(왕좌, 카운터 3, 질문 대기 자리, 간판)를 생성.
6. **키는 서버에만.** LLM 호출은 전부 서버 `HttpService`. TTS는 Roblox 내장(`AudioTextToSpeech`)이라 키 불필요.

## 4. 모듈 지도

| 파일 | 역할 |
|---|---|
| `server/Main.server.luau` | 리모트 생성, 월드 빌드, `RoundManager.start` |
| `server/RoundManager.luau` | lobby/countdown/running/closing/results, 가게 배정, 왕좌에 앉히기, 리더보드, 병렬 평가 |
| `server/ShopEngine.luau` | 사장 1명 × 라운드 1회: 카운터 루프 3개, 질문 큐, 칭찬/경고/해고/채용, 판매 검증, 규칙 위반, 기록 |
| `server/CustomerGen.luau` | 랜덤 손님/직원 생성 + 각자 TTS 목소리(VoiceId/Pitch/Speed) |
| `server/AgentRuntime.luau` | 손님/직원/평가자 프롬프트 + JSON 파싱 |
| `server/LlmClient.luau` | OpenAI 호환 호출, `jsonMode`(400이면 자동 해제) |
| `server/Config.luau` | 라운드, 직원 수, 채용비, 질문 대기시간, 점수 가중치, 입소문, TTS 목소리 목록 |
| `server/Packs/CafeShift.luau` | 메뉴 6종, 재고, 손님 범위, 직원 성격 5종, 규칙 3종×3옵션, 프롬프트 |
| `client/Main.client.luau` | 로비, HUD, 직원 카드, 규칙 칩, 질문 카드, TTS, 왕좌 오버뷰 카메라, 결과/디브리프 |

리모트: S→C `Phase, State, Questions, Speak, Debrief, Toast, Leaderboard, Timer` /
C→S `StartRound, Continue, SetPolicy, Answer, StaffAction`.

## 5. 현재 상태 (2026-11-11)

- 비공개 게시: "KidSim - Cafe Shift" (placeId 78858397239070), Allow HTTP Requests On.
- 개발 키: `DevSecrets.luau`(OpenAI 호환). 기본 Config는 GMI Cloud.
- Studio MCP 1인 실측(사장 시점): 3분에 손님 21명, $43, 평균 3.9★, 74점.
  직원 질문("30% 할인 줘도 돼요?") → 버튼 응답, 경고, 해고 → 새 직원 채용, 미응답 타임아웃,
  디브리프의 성격 공개(Theo=Pushy seller, Jake=Pushover, Ruby=Grumpy)와 평가 JSON까지 모두 동작.
  LLM 실패/평가 폴백 0회. 스크린샷 `demo/owner-*.jpg`.
- TTS: Studio Play 클라이언트에서 `AudioTextToSpeech:LoadAsync()` → `Success` 확인. 실제 소리는
  MCP로는 들을 수 없어 미확인(사람이 Studio에서 들어봐야 함).
- **2인 멀티플레이는 아직 실제 검증 안 됨**(MCP는 1인 Play만). Test → Clients and Servers로 확인 필요.

## 6. 알려진 공백 / 다음 과제 (퀄리티 컨트롤)

1. **성격이 행동으로 충분히 드러나는가.** 실측 라운드에서 Pushover/Pushy seller가 규칙 위반을 0회 했음
   (Pushover는 오히려 물어보러 옴). 위반 판정은 할인만 기계로 잡고, "강매"는 손님 별점으로만 드러남.
   - 방향: 성격 프롬프트 강도 조절 + 성격별 "위반 성향" 수치를 서버가 주입(예: Pushover는 손님이 할인 요구 시
     n% 확률로 규칙 초과 할인 지시), 강매는 `selling` 규칙 대비 "손님이 거절 후에도 추가 제안" 횟수로 판정.
   - 성격별 행동을 자동 회귀 테스트하는 하네스(서버 컨텍스트에서 가상 손님과 N회 시뮬, 위반율 측정) 필요.
     단, MCP `execute_luau` 서버 컨텍스트에선 LLM 호출이 막힘(아래 §7) → 게임 내 디버그 커맨드로 돌려야 함.
2. **LLM이 `items`를 빠뜨리거나 금액을 틀리게 말함**(합의 $7, 품목은 $5). 서버가 메뉴가로 클램프하고 경고 로그.
3. **2인 실검증**(가게 배정, 리더보드, 중간 입장, 퇴장 시 가게 해제).
4. **TTS 한도**: 경험 전체 분당 1+6×접속자. 클라이언트에서 분당 6회 + 근처(24스터드)만 + 질문 우선으로 제한.
5. **아이 입력이 없으므로** 텍스트 필터링 이슈는 줄었지만, LLM 출력(말풍선) 모더레이션은 프롬프트 가드레일뿐.
6. 비주얼: 블록 NPC, 말풍선은 카운터당 하나(최신 화자)만. 데모용으로 의상/애니메이션 개선 여지.
7. 업종 확장: 카페 외 팩(예: 보험사/은행 창구 — "고객 상담, 규정, 예외 승인")은 팩 모듈만 추가하면 됨.

## 7. 에이전트 작업 규칙

- **`src/server/DevSecrets.luau`는 절대 커밋/출력 금지.** 로컬 HTTP 서버로 `src/`를 서빙하지 말 것(이 파일 포함).
- 빌드: `rojo build -o kidsim.rbxlx`. Studio에서 MCP로 스크립트를 고쳤다면 같은 변경을 `src/`에도
  반영하고 길이+해시 비교로 동기화를 확인할 것(반대도). `luau-compile --null <file>`로 문법 확인 가능
  (`brew install luau`).
- Studio 에디트 `execute_luau`는 Assistant HTTP allowlist 때문에 localhost 불가, 서버 컨텍스트 `execute_luau`의
  LLM 호출은 "Assistant HTTP permissions are not configured"로 실패(게임 자체 호출은 정상).
  스크립트 동기화는 `execute_luau`로 Source 직접 설정 또는 `multi_edit`.
- **UI:** 새 `UIListLayout`은 반드시 `SortOrder = LayoutOrder`(클라이언트 `list()` 헬퍼). 월드 BillboardGui에
  `AlwaysOnTop = true`를 쓰면 Studio Play에서 안 보였음 — 쓰지 말 것. Gotham 폰트에 `▸` 같은 기호가 없어
  네모로 나옴(`»`는 됨).
- **Studio MCP 플레이 테스트:**
  - 위젯 경로: `KidSimUI.LobbyOverlay.LobbyCard.StartButton`, `KidSimUI.StaffPanel.Staff{1..3}.Actions.{PraiseButton,WarnButton,FireButton}`,
    `KidSimUI.Rules.Rule_{discounts,selling,askMe}`, `KidSimUI.QuestionCard.Option{n}`, `KidSimUI.DebriefOverlay.DebriefCard.Content`.
  - `execute_luau`로 카메라 타입을 바꾸면 Assistant가 Custom으로 되돌림 — 카메라 확인은 실제 플레이 흐름으로.
  - 로그 확인: `[KidSim] LLM call failed` / `Evaluator fell back` / `Sale settled below the agreed price` /
    `Text-to-speech failed`.
- 팩 수치·점수식·규칙을 바꾸면 §2, README를 같이 갱신할 것.
