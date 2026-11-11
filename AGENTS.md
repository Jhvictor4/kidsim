# AGENTS.md — KidSim 기획 현황과 작업 규칙

이 문서는 이 리포에서 일하는 에이전트(와 사람)를 위한 **현재 기획 스냅샷**입니다.
구조 설명은 `README.md`, Studio 수동 설정은 `SETUP.md`를 보세요. 여기에는 "무엇을
왜 이렇게 만들었는지", "지금 어디까지 왔는지", "다음에 뭘 고쳐야 하는지"를 적습니다.

마지막 갱신: 2026-11-11 (Linear AEO-1441)

---

## 1. 한 줄 컨셉

**"Isaac Sim, but for kids."** 로봇이 시뮬레이터에서 먼저 연습하고 현실로 나가듯,
아이가 Roblox 안에서 실제 생활 기술(돈 관리, 고객 응대, 협상, 거절하기)을 연습하고
마지막 **디브리프**에서 "방금 한 게 현실에서는 이렇게 불린다"를 확인합니다.

- 대상: 10–13세. 언어: 영어(현재).
- 출신: c0mpiled-18 YC Startup School 해커톤. 피치 프레임은 YC RFS "The $15-an-Hour Expert".
- 핵심 산출물: **90초 데모 영상** (thesis 카드 → 할인 요구 → 컴플레인 + 코치 힌트 → 디브리프).
  디브리프가 펀치라인이므로 반드시 깨끗하게 보여야 합니다.

## 2. 플레이 흐름

```
Intro 카드 ("Start my shift")
  → Shift: 손님(incident) 5명 순서대로
       각 손님: 고정 오프닝 대사 → 아이가 자유 채팅(선택) / Coach 버튼(1회)
                → 선택지 버튼 클릭 = 결과 확정, 미터 변화
  → Close ("Closing up the shop...")
  → Debrief (미터 전→후, 연습한 기술, 잘한 점/주의할 점, 현실 전이, 다음 드릴)
  → "Run another shift"로 재시작
```

## 3. 설계 원칙 (바꾸기 전에 합의할 것)

1. **결과는 결정적, LLM은 말만 한다.** 미터·재고 변화는 오직 선택지의 `deltas`로
   결정되고 서버가 권위를 가집니다. LLM은 손님 대사, 코치 힌트, 디브리프 평가만
   담당합니다. 모델 호출이 실패해도 게임은 끝까지 돌아갑니다(스크립트 폴백).
2. **엔진은 팩을 모른다.** `SimEngine`에는 카페 개념이 0개입니다. 새 시나리오
   (법정, 협상, 회계 등)는 `src/server/Packs/`에 새 모듈 하나 + `Main.server.luau`의
   `ACTIVE_PACK` 교체로 끝나야 합니다. 팩 계약은 `src/shared/Types.luau`.
3. **월드도 코드다.** 맵은 `WorldBuilder`가 생성합니다. `.rbxlx`는 빌드 산출물(gitignore).
4. **키는 서버에만.** LLM 호출은 전부 서버 `HttpService`. 클라이언트 스크립트나
   ReplicatedStorage에 키가 닿으면 안 됩니다.

## 4. LLM 페르소나 (프롬프트는 팩이 공급)

| 페르소나 | 역할 | 제약 |
|---|---|---|
| Counterpart | 손님 연기, 자유 채팅 응답 | 1–2문장, 연령 가드레일, 가격/월드 변경 불가 |
| Coach | 힌트 | 사건당 1회(`Config.COACH_HINTS_PER_INCIDENT`), 정답 버튼을 말하지 않음 |
| Evaluator | 디브리프 JSON 생성 | 로그 근거로만 판단, **기술은 최대 3개**(`debriefTemplate`) |

평가 JSON 파싱 실패 시 `fallbackEvaluation`(결정적 디브리프)로 대체하고
`[KidSim] Evaluator fell back...` 경고를 남깁니다. 개별 호출 실패는 `[KidSim] LLM call failed`.

## 5. Cafe Shift 팩 (현재 유일한 팩)

시작값: Cash $20 · Reputation 60/100 · Waste 0 · 재고 Coffee 10 / Croissant 5 / Cookie 8.
메뉴: Coffee $4 · Croissant $3 · Cookie $2.

| # | 손님 | 상황 | 연습 기술 | 선택지 (의도된 학습) |
|---|---|---|---|---|
| 1 | Maya | 단골의 바쁜 아침 주문 | 업셀, 고객 응대 | 그냥 서빙 $7 / 쿠키 제안 $9 (+평판) |
| 2 | Mr. Park | 50% 할인 요구 | 협상, 경계 지키기 | 정가 고수 / 반값(이익 0) / 정가+무료 쿠키(최선) |
| 3 | Grandma Ro | 잘못 나간 주문 컴플레인 | 고객 응대, 실수 인정 | 새 크루아상(평판↑↑, waste+1) / 환불 / "내 근무 아님"(평판↓↓) |
| 4 | Dev | 크루아상 5개 급주문(재고 부족) | 재고, 정직 | 남은 것+쿠키 / 쿠키 박스 / 일단 약속(평판↓) |
| 5 | Joon | 돈 없는 아이의 공짜 요구 | 경계, 공정 거래 | 테이블 닦고 얻기(최선) / 그냥 주기 / 친절한 거절 |

데모용 "좋은 플레이" 기준 결과 (2026-11-11 실측): **Cash $20→$47, Reputation 60→84, Waste 0→1.**

## 6. 현재 상태 (2026-11-11)

- 비공개 게시 완료: "KidSim - Cafe Shift" (placeId 78858397239070), Allow HTTP Requests On.
- LLM: 개발용 `DevSecrets.luau`로 OpenAI 호환 엔드포인트 사용 중 (기본 Config는 GMI Cloud).
- Studio MCP(`roblox-studio`)로 처음부터 디브리프까지 완주 확인. LLM 실패/폴백 0회.
- 수정됨: 모든 `UIListLayout`이 기본값 `SortOrder=Name`이라 LayoutOrder가 무시되고
  인트로/디브리프의 버튼이 카드 맨 위로 올라가던 버그 → 전부 `SortOrder=LayoutOrder`로 고정.
  전후 스크린샷은 `demo/`.

## 7. 알려진 기획 공백 (우선순위 순)

1. **자유 채팅이 결과에 영향을 주지 않음.** 점수는 버튼으로만 바뀌고, 선택지가 처음부터
   보여서 채팅을 건너뛰어도 됩니다. "LLM 롤플레이로 연습한다"는 차별점이 약해지는 지점.
   - 방향: 첫 발화 후에 선택지 공개 + Evaluator/Counterpart가 아이의 말(공손함·명확성·대안 제시)을
     짧게 채점해 평판 ±1~2 정도의 작은 보정치와 디브리프 근거로만 사용. 결정성은 버튼이 유지.
2. **선택지 라벨이 정답을 노출함** ("Say it wasn't your shift — no refund" 등). 고민할 여지가 적음.
3. **디브리프 전이가 일반적/부정확할 수 있음.** 실측에서 "In the real world"가 "카페·고객 서비스
   직업"에 그쳤고, Next drill이 하지도 않은 과잉약속을 지적. 아이의 실제 일상(용돈, 친구, 학교
   바자회) 예시를 강제하고, 로그에 없는 행동은 언급 금지하도록 평가 프롬프트 보강 필요.
4. **옳은 행동이 벌점처럼 보임.** 크루아상 교체(정답)가 Waste ▲ 빨간색 + "What to watch"로 표시됨.
   waste의 의미(실수 비용 vs 낭비)를 디브리프에서 구분하거나 표시 방식 조정 필요.
5. **트레이드오프가 약함.** 잘 플레이하면 모든 미터가 오르기만 함. 재고·시간 압박 등 진짜 선택의
   긴장이 부족.
6. **데모 시간.** 손님 5명 × LLM 대기 시간이면 90초 초과. 촬영 시 2–3명 구간 편집 전제.
7. 소소한 UX: 대기 표시 "•••"가 손님이 아니라 플레이어 이름 옆에 붙음(`SimEngine.runIncident`에서
   플레이어 대사 송출 직후 Busy 전송). 디브리프 evidence 줄바꿈 들여쓰기가 공백 기반이라 둘째 줄이 깨짐.

## 8. 에이전트 작업 규칙

- **`src/server/DevSecrets.luau`는 절대 커밋/출력 금지.** (gitignore됨) 키 값을 로그, 메시지,
  외부 서비스에 남기지 말 것.
- 빌드: `rojo build -o kidsim.rbxlx`. Studio에서 MCP로 스크립트를 고쳤다면 같은 변경을 `src/`에도
  반영해 동기화를 유지할 것(반대도 마찬가지).
- **UI 레이아웃:** 새 `UIListLayout`은 반드시 `SortOrder = Enum.SortOrder.LayoutOrder`를 설정하고
  순서가 중요한 자식에는 `LayoutOrder`를 명시. 기본값(Name)은 같은 클래스 이름끼리 순서를 뒤섞음.
- **Studio MCP로 플레이 테스트할 때:**
  - 마우스 좌표는 스크린샷 픽셀이 아니라 GUI `AbsolutePosition` 좌표계(뷰포트 크기 기준).
  - UI 인스턴스 이름이 전부 `Frame`/`TextLabel`이라 `instance_path`로 찍으려면 런타임에 이름을
    바꿔야 함(지금은 LayoutOrder 정렬이라 이름을 바꿔도 레이아웃이 안 깨짐).
  - 채팅: TextBox 클릭 → `textInput`(별도 호출) → Reply 버튼 클릭. `textInput`+`Return`을 한 배치로
    보내면 텍스트가 유실되는 경우가 있었음.
  - LLM 이상 여부는 `get_console_output`에서 `[KidSim] LLM call failed` / `Evaluator fell back` 확인.
- 팩 수치를 바꾸면 §5 표와 데모 기준 결과를 같이 갱신할 것.
