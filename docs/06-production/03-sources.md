# 공식 출처와 설계 가정

[전체 문서 트리](../README.md) · [상위 분야](README.md)

> 문서 ID: PROD-03 · 버전: 2.0 · 기준일: 2026-11-11 · 상태: 구현 전 제작 기준안

## 무엇이 근거이고 무엇이 설계인가

확인일은 2026-11-11이다. 기술 기능·지원 범위·결제 이벤트의 근거는 해당 제품의 공식 문서다. 오픈타운의 고객 수, 가격, 확률 가중치, 경영일 길이, 연구 시간, 교육 목표, 경쟁 구조는 이번 프로젝트의 초기 설계값이다. 공식 문서가 이 수치의 재미·수익성·교육 효과를 입증하지는 않는다.

각 플랫폼 문서의 ‘공식 근거’ 절에는 적용한 API와 URL을 함께 기재했다. 아래 표는 중요한 출처를 주제별로 찾기 위한 시작점이다. 링크가 이동하면 해당 공식 사이트의 새 경로와 확인일을 갱신한다.

## 웹 구현 근거

| 출처 | 확인한 내용 | 적용 문서 |
|---|---|---|
| [Three.js Fundamentals](https://threejs.org/manual/pages/fundamentals.html) | 장면·카메라·렌더러와 3D 표현 구조 | 웹 구현의 렌더링 책임 |
| [Three.js WebGLRenderer](https://threejs.org/docs/pages/WebGLRenderer.html) | WebGL2 렌더러와 지원 범위 | 브라우저 지원·초기 렌더러 |
| [Three.js Cleanup](https://threejs.org/manual/pages/cleanup.html) | geometry·material·texture의 명시적 수명 관리 | 장면 전환·자원 해제 |
| [Colyseus State Synchronization](https://docs.colyseus.io/state) | 서버의 상태 변경과 클라이언트 동기화 | StageRoom와 공개·개인 상태 |
| [Colyseus Rooms](https://docs.colyseus.io/room) | 방 설정과 메시지 처리 | 연결·입장·실행 주기 |
| [Colyseus Reconnection](https://docs.colyseus.io/room/reconnection) | 재접속 처리 | 60초 유예의 웹 어댑터 |
| [Colyseus Scalability](https://docs.colyseus.io/scalability) | 방 소유 프로세스와 공유 계층 | 다중 프로세스 확장 |
| [PostgreSQL Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html) | 격리·충돌·재시도 조건 | 원장·예약·명령 트랜잭션 |
| [MDN WebSocket](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket) | 브라우저 연결 API와 역압 제약 | 송수신 큐·재동기화 |

이 근거로 채택한 전체 구조는 [웹 구현 문서](../05-platforms/01-web-threejs.md)에서 확인한다. 라이브러리의 상태 동기화가 영구 결제·지갑·복구를 자동으로 해결한다는 주장은 하지 않는다.

## 결제 근거

| 출처 | 확인한 내용 | 적용 |
|---|---|---|
| [Stripe Webhooks](https://docs.stripe.com/webhooks) | 이벤트 검증·중복·도착 순서 대응 | 외부 증빙 수신과 단회 처리 |
| [Stripe Checkout Fulfillment](https://docs.stripe.com/checkout/fulfillment.md?ui=full-page) | 완료 페이지에만 의존하지 않는 지급·결제 상태 확인 | DG 지급과 재시도 |

Stripe는 검토 가능한 참조 구현이다. 특정 국가·사업자·상품의 서비스 이용 가능성을 이 문서가 보장하지 않는다. 실제 제공자·정산 통화·가격·세금·환불 고지는 해당 사업 조건을 확정한 뒤 [웹 결제와 운영](../05-platforms/02-web-payments-and-ops.md)의 제공자 어댑터와 출시 항목에 반영한다. 게임 문서에 실제 카드 정보나 결제 비밀을 넣지 않는다.

## 대체 플랫폼 근거

| 출처 | 확인한 내용 | 적용 |
|---|---|---|
| [Roblox Data Stores](https://create.roblox.com/docs/cloud-services/data-stores) | 세션을 넘어 보존할 데이터와 저장 API | 대체 저장 어댑터 |
| [Roblox MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService) | 상품 정보와 영수증 처리 API | 대체 결제 어댑터 |

이 문서의 첫 구현 대상은 웹이다. 대체 플랫폼의 저장·계정·결제·채팅에 관한 추가 출처와 공통 계약을 충족하기 위한 차이는 [Roblox 어댑터](../05-platforms/03-roblox-adapter.md)에 모았다. 플랫폼별 통화를 공통 TC·DG 정의에 섞지 않는다.

## 교육·시장 관련 주장 범위

이 게임은 요구 확인, 원가와 매출 구분, 약속 이행, 검증, R&D와 시장 적합성을 경험하게 하려는 설계다. 실제 창업 성공률, 금융 성과, 전문 직무 능력, 사회성 향상에 관한 검증된 교육 상품이라고 주장하지 않는다.

사용자 테스트에서는 처음 보는 사례로 개념을 적용하는지 확인한다. 클릭 수·접속 시간·매출 증가를 곧바로 교육 효과라고 해석하지 않는다. 검증 계획은 [플레이테스트와 교육 효과 평가](02-playtest-and-metrics.md)에 있다.

## 구현 전 다시 확인할 것

- 실제 사용할 패키지와 서버·클라이언트의 호환 버전을 lockfile로 고정한다.
- 문서에 나온 API의 현재 이름·오류·지원 범위를 공식 자료에서 확인한다.
- 기준 기기와 네트워크에서 성능·재접속 목표를 측정한다.
- 실제 결제 제공자와 상품 자격·환불·대금 상태를 확인한다.
- 외부 모델을 쓰면 모델 없이도 동일 핵심 게임이 작동하는지 검증한다.

확인되지 않은 부분은 작업을 막는 포괄적 경고가 아니라 해당 기능의 출시 관문으로 관리한다. 공통 규칙·튜토리얼·시장 시뮬레이션은 그와 독립적으로 구현할 수 있다.

## 이 패키지의 문서 검증 결과

- Markdown 40개, 상대 문서 링크 382개를 확인했으며 누락된 연결은 없었다.
- 표 136개와 JSON 예시 3개의 문법·구조를 검사했다.
- 공통 8컷과 업종별 10컷씩 총 48컷, 고유 아이템 ID 36개, 사건 선택 24개를 확인했다.
- 공통 구현 분야에 플랫폼 제품·API 명칭이 섞이지 않는지 확인했다.
- 4업종 기본 거래의 원가·매출·운영비·XP 예시를 대조했다.
- 운영비 예약식을 18,030개의 정수 입력 조합으로 과금 경계 횟수와 비교했다.
- SI 수락 가격 보존, 튜토리얼의 사건 순서·즉시 회고, 환불 후 같은 lot의 남은 DG 보존을 교차 검토했다.

위 결과는 문서와 예시 계산의 검증이다. 실제 게임 실행, 결제 사업자 연동, 동시 접속 부하, 사용자 재미와 학습 효과 검증은 구현 단계의 별도 작업이다.

## 연관 문서

- [웹 구현의 전체 근거](../05-platforms/01-web-threejs.md)
- [웹 결제](../05-platforms/02-web-payments-and-ops.md)
- [대체 플랫폼](../05-platforms/03-roblox-adapter.md)
- [검증 계획](02-playtest-and-metrics.md)
