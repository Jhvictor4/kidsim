# OPEN TOWN 창업 경쟁 타이쿤 문서

> 버전 2.0 · 기준일 2026-11-11 · 상태: 구현 전 제작 기준안

**내 사업을 운영하고 발전시켜, 같은 상권의 고객이 선택하는 가게와 회사를 만든다.**

카페·음식점·소프트웨어·SI를 선택하는 실시간 멀티플레이 타이쿤이다. 웹을 첫 구현 대상으로 삼고, 공통 게임 규칙과 구현 계약은 플랫폼과 분리한다. 기존 v1의 소유·꾸미기·교육·재화 구상을 계승하면서 경쟁·현실적 운영·선택의 후속 결과를 중심으로 다시 설계했다.

## 이 문서를 사용하는 방법

이 폴더 전체를 유지한 채 README.md를 Markdown 뷰어나 저장소에서 연다. 아래 문서 트리의 링크를 누르면 하위 문서로 이동하고, 각 문서 상단에서 전체 트리나 상위 분야로 돌아갈 수 있다. 개별 파일만 분리하면 상대 링크의 대상이 함께 있지 않을 수 있으므로 전체 ZIP의 폴더 구조를 유지하는 방법을 권한다.

문서는 총 **40개 Markdown 파일**이다. 공통 도입 8컷과 업종별 10컷씩의 스토리보드, 합계 **48컷**, 튜토리얼 12상태, 핵심 선택 사건 8개와 24개 옵션, 아이템 카탈로그 36건을 수록한다. 구현 명세와 백로그·검증 명세도 같은 트리에 있다.

## 가장 먼저 볼 내용

1. [게임 비전과 MVP](00-overview/01-vision-and-mvp.md): 공개 MVP에서 약속하는 범위를 확인한다.
2. [공통 스토리보드](03-experience/03-storyboard-common.md): 업종 선택에서 첫 운영으로 이어지는 경험을 본다.
3. [게임 공통 구현 명세](04-implementation/01-engine-neutral-spec.md): 상태·명령·모듈 경계를 읽는다.
4. [Three.js 웹 구현](05-platforms/01-web-threejs.md): 공통 명세를 실제 웹 스택에 연결한다.

## 문서 트리

- [기획의 기준](00-overview/README.md)
  - [게임 비전과 MVP 범위](00-overview/01-vision-and-mvp.md) — 제품 약속·공개 범위·완료 증거
  - [설계 결정과 이전 버전 변경](00-overview/02-design-decisions.md) — v1에서 유지·수정·폐기한 기준
  - [용어와 문서 원본 찾기](00-overview/03-glossary.md) — 수치·상태·규칙의 기준 문서
- [공통 게임 시스템](01-game/README.md)
  - [핵심 반복과 시간](01-game/01-core-loop-and-time.md) — 영업·마감·약속·오프라인·재접속
  - [시장 수요와 NPC 고객](01-game/02-market-and-npc.md) — 한정 수요·고객 선택·예약·NPC 경쟁자
  - [운영 품질과 R&D](01-game/03-operations-quality-rnd.md) — 품질·시장 적합성·공정·연구
  - [명성과 경쟁](01-game/04-reputation-and-competition.md) — 고객 경험·회복·공정한 비교
  - [선택 분기와 소형 AI 사건](01-game/05-choices-and-ai-events.md) — 조건·선택·후속 결과·경량 AI
  - [재화와 아이템 설정 원본](01-game/06-economy-and-items.md) — TC·DG·PB·XP·가격·연구·카탈로그36건
- [네 가지 창업 유형](02-businesses/README.md)
  - [카페](02-businesses/01-cafe.md) — 음료 품질·대기·원재료·단체 주문
  - [음식점](02-businesses/02-restaurant.md) — 조리·재료 조건·준비·납기
  - [소프트웨어 회사](02-businesses/03-software.md) — 요구 조사·검증·출시·후속 지원
  - [SI 회사](02-businesses/04-si.md) — 범위·합의·통합·검수·변경 요청
- [세계·튜토리얼·스토리보드](03-experience/README.md)
  - [세계관과 레벨 디자인](03-experience/01-world-and-level-design.md) — 연두항·6개 필지·동선·배치·제작 목록
  - [업종 선택과 튜토리얼](03-experience/02-onboarding-and-tutorial.md) — TUT00~TUT11, 완료·생략·재개
  - [공통 도입 스토리보드](03-experience/03-storyboard-common.md) — CT01~CT08에서 네 업종으로 분기
  - [카페 스토리보드](03-experience/04-storyboard-cafe.md) — CF01~CF10, 선택·후속 효과·복구
  - [음식점 스토리보드](03-experience/05-storyboard-restaurant.md) — FD01~FD10, 선택·후속 효과·복구
  - [소프트웨어 스토리보드](03-experience/06-storyboard-software.md) — SW01~SW10, 선택·후속 효과·복구
  - [SI 스토리보드](03-experience/07-storyboard-si.md) — SI01~SI10, 선택·후속 효과·복구
  - [화면 설계와 플레이어 설명서](03-experience/08-ui-and-player-manual.md) — 조작·운영·연구·마감·복구·접근성
- [플랫폼 중립 구현 명세](04-implementation/README.md)
  - [게임 공통 구현 명세](04-implementation/01-engine-neutral-spec.md) — 모듈·상태·포트·명령·불변식
  - [데이터와 메시지 계약](04-implementation/02-domain-data-contracts.md) — 도메인 모델·요청·응답·오류·원장
  - [실시간과 영구 저장](04-implementation/03-realtime-and-persistence.md) — 권위·동시성·복구·T01~T24
  - [검증 명세와 인수 기준](04-implementation/04-test-and-acceptance.md) — F01~F24·기술 검증·출시 관문
  - [콘텐츠 제작 명세](04-implementation/05-content-authoring.md) — 업종·상품·사건·분기 정의와 검사
- [플랫폼별 적용](05-platforms/README.md)
  - [Three.js 웹 구현 기준](05-platforms/01-web-threejs.md) — 웹 우선 스택·장면·서버·배포·성능
  - [웹 결제와 운영](05-platforms/02-web-payments-and-ops.md) — 실화폐→DG·검증·지급·환불·운영
  - [Roblox 어댑터 기준](05-platforms/03-roblox-adapter.md) — 공통 계약의 대체 적용·차이·검증 한계
- [제작과 검증 운영](06-production/README.md)
  - [제작 단계와 구현 백로그](06-production/01-roadmap-and-backlog.md) — M0~M5·DEV01~DEV20·담당과 의존성
  - [플레이테스트와 교육 효과 평가](06-production/02-playtest-and-metrics.md) — 재미·경쟁·이해·학습 전이 관측
  - [공식 출처와 설계 가정](06-production/03-sources.md) — 기술 근거·변경 확인·추정의 범위

## 역할별 추천 경로

| 역할 | 읽는 순서 |
|---|---|
| 제품·기획 | 비전 → 공통 시스템 → 업종 → 스토리보드 → 플레이테스트 |
| 게임·서버 개발 | 비전 → 경제 원본 → 공통 구현 → 데이터 → 실시간·저장 → 테스트 → 플랫폼 |
| 클라이언트·UI 개발 | 세계·레벨 → 튜토리얼 → 스토리보드 → UI → 메시지 계약 → 웹 구현 |
| 아트·연출 | 세계·레벨 → 4업종 → 48컷 스토리보드 → 아이템 → 웹 성능 예산 |
| QA·운영 | 설계 결정 → 경제 → 기능·기술 테스트 → 결제·운영 → 플레이테스트 |

## 핵심 설계 결정

- 최대 6명이 한 스테이지에서 운영하며 같은 업종도 여러 명 선택할 수 있다.
- 각 수요에 호환되는 업체끼리 같은 고객을 두고 경쟁한다. 시장의 수요와 외부 선택지를 보존한다.
- 경영일 20분은 보고 주기다. 현실의 하루나 강제 연속 접속 단위가 아니다.
- 약속한 영업·납품·품질 관리의 결과가 남고, 정상 마감한 미접속 시간은 동결한다.
- TC·DG·PB·XP는 유지한다. DG는 표현용이며 웹 실화폐 결제 방식은 별도 문서에서 정의한다.
- 주문을 받기 전에 원가와 완료까지 필요한 운영비를 예약해 음수 지갑과 납품 교착을 막는다.
- 선택과 후속 결과는 저장한다. 경량 AI는 허용된 사건·문장을 제안하고 게임의 정산 권한은 갖지 않는다.
- 첫 내부 완성 구간은 카페지만 공개 MVP에는 네 업종이 모두 포함된다.

## 수치와 상태의 원본

같은 규칙을 여러 파일에서 임의로 바꾸지 않는다. [경제와 아이템](01-game/06-economy-and-items.md)은 숫자 원본, [공통 구현](04-implementation/01-engine-neutral-spec.md)은 상태·명령 원본, [콘텐츠 제작](04-implementation/05-content-authoring.md)은 정의 형식의 원본이다. 상세 경로는 [용어와 원본 찾기](00-overview/03-glossary.md)를 따른다.

## 검증 범위

문서 연결·필수 항목·ID·예시 계산을 검토한 설계 패키지다. 실제 게임 실행·부하·결제·재접속·재미·학습 효과를 검증한 빌드는 아니다. 수익·가격·성능·학습 목표는 초기 가정이며, [검증 명세](04-implementation/04-test-and-acceptance.md)와 [플레이테스트 계획](06-production/02-playtest-and-metrics.md)에 따라 구현 후 확인한다.

이전 파일과 충돌하는 경우 이번 패키지의 v2 기준을 적용한다. 변경 이유는 [설계 결정](00-overview/02-design-decisions.md)에 기록했다.
