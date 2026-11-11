# Roblox 대체 적용 명세

버전 2.0 · 확인일 2026-11-11 · 상태: 대체 플랫폼 검토안, 웹 MVP의 필수 구현 범위 아님  
[문서 트리](../README.md) / [플랫폼 문서](README.md)

## 1. 이 문서의 역할

이번 제작 우선 대상은 웹이다. 이 문서는 향후 Roblox에 적용할 때 바뀌는 부분을 모아 둔다. 카페·음식점·소프트웨어·SI, 6명 상권, 수요 경쟁, 품질·연구·명성, 원가·운영비 예약, 선택 결과는 [공통 구현 명세](../04-implementation/01-engine-neutral-spec.md)를 유지한다.

웹의 화면 코드와 서버 코드를 그대로 실행하는 이식은 전제하지 않는다. 공통 데이터와 fixture를 재사용하고 Luau 어댑터로 동작을 맞춘다. 계정·지갑을 웹과 자동 공유하거나 서로 송금하는 기능은 MVP 범위에 없다.

## 2. 포트 대응

| 공통 포트·개념 | Roblox 적용 | 별도 확인 |
|---|---|---|
| IdentityPort | Players의 인증된 UserId를 내부 ID로 매핑 | 클라이언트가 보낸 UserId 신뢰 금지 |
| PresentationPort | Workspace, Camera, GUI, LocalScript | 서버 상태의 표시·입력만 담당 |
| CommandPort | RemoteEvent 중심 요청·결과 | C01~C20 봉투와 권한·속도·길이 검사 |
| Simulation | 서버 서비스와 제한된 갱신 루프 | 이동 소유권이 경제 권위가 되지 않음 |
| DurableStorePort | DataStoreService와 UpdateAsync | 한 키의 원자적 변경과 여러 키 복구를 구분 |
| Stage discovery | MemoryStoreService | 일시 좌석·대기열, 영구 원장 금지 |
| Notification | MessagingService | 알림 보조. 알림 도착만으로 지급하지 않음 |
| PaymentPort | MarketplaceService 개발자 상품 영수증 | Robux 구매 → DG 지급. 웹 checkout 직접 재사용 안 함. |
| TextPolicyPort | TextChatService와 적합한 텍스트 필터 | 현재 권한·필터·연령 접근 규칙 적용 |
| Asset pipeline | Studio용 모델·텍스처·애니메이션 | 격자·접근점·functionBase 보존 |

서버가 모든 원격 입력을 검증해야 한다는 Roblox 공식 지침에 따라, 소유권·유형·범위·거리·빈도를 검사한다. ProximityPrompt나 화면 버튼이 호출 경로라는 이유로 신뢰하지 않는다. [R01]

## 3. 데이터 저장의 차이

사용자 키에 지갑, 아이템 소유권, 진행 중 주문·예약, 구매 처리 ID, 선택 효과 이력, 소유 세대를 함께 둔다. UpdateAsync 변환은 전달받은 최신 값과 expectedRevision을 검사하고, 외부 부작용 없이 새 값을 계산한다. 충돌로 변환이 재실행될 수 있으므로 안에서 결제 호출·추가 지급·알림 발행을 직접 실행하지 않는다. [R02]

한 키의 변경이 안전하다고 여러 사용자·스테이지 키가 동시에 원자적으로 변경되는 것은 아니다. 공통 명세의 ‘수요 예약 준비 → 사용자 원가·운영비 예약 → 확정 발표’를 영구 실행 기록으로 구현해야 한다. 준비 단계의 예약은 완료·해제 중 하나로 재처리할 수 있어야 한다.

DataStore 요청에는 지연과 한도가 있으므로 이동 10Hz나 경제 tick 1초마다 모든 프로필을 쓰지 않는다. 영구 의미가 있는 거래는 저장 완료 후 성공을 알리고, 위치·애니메이션은 별도 일시 상태로 둔다. 저장이 막히면 신규 수요 수락과 소비를 제한하며 완료되지 않은 기록을 성공처럼 보여주지 않는다. 공식 플레이어 데이터 지침도 저장 한도, 초기 기본값 덮어쓰기, 세션 잠금 문제를 다룬다. [R03]

### 검증이 필요한 추가 구현

- 스테이지 결정 기록과 사용자 profile 반영 사이의 장애 복구.
- 새 스테이지 소유 세대가 각 참가자 profile에 적용되기 전의 이전 실행자 차단.
- 이미 확정한 이전 세대의 거래를 중복 없이 완료하는 처리와, 신규 이전 세대 요청의 거부 구분.
- 원장·중복 키 증가에 대한 크기·보관 계획. 구매 증빙 키를 단순 TTL로 삭제하지 않음.
- 제한 상황에서 6명 수요 예약·영업·고정비·선택 결과를 저장할 수 있는 처리량.

위 조건과 T05·T07·T10이 검증되기 전에는 웹판과 같은 복구 보장을 충족했다고 표시하지 않는다. MemoryStore는 빠른 일시 데이터를 위한 저장소이며 만료될 수 있으므로 영구 경제 기록의 대체물로 쓰지 않는다. [R04]

## 4. 결제 적용

Roblox판의 DG 팩은 개발자 상품 ID에 연결한다. 웹판의 실제 통화 가격과 같은 값으로 환산하지 않고 플랫폼에서 조회한 실제 상품 정보를 보여준다. 구매창이 닫혔다는 이벤트를 지급 근거로 쓰지 않는다.

이 적용안은 `MarketplaceService.ProcessReceipt`를 영수증 진입점으로 선택한다. `PurchaseId`를 영구 중복 키로 사용하고, DG와 처리 기록을 같은 사용자 데이터 변경에 저장한 뒤 `PurchaseGranted`를 반환한다. 실패하면 `NotProcessedYet`로 두고 미해결 구매를 안내한다. 공식 API에는 새로운 `BindReceiptHandler`도 있으므로 실제 구현에서 어느 경로를 채택했는지 고정해야 한다. 두 경로에서 같은 상품을 각각 지급하지 않는다. [R05]

ProcessReceipt에는 자동 시간 기반 재시도가 보장되지 않으며 같은 구매가 여러 서버에 전달될 수 있다. 클라이언트에게 추가 구매를 복구 방법으로 안내하지 않는다. 같은 PurchaseId를 재처리할 때 기존 지급 결과를 확인한다. [R05]

웹의 refund·dispute webhook과 동일한 이벤트가 Roblox에서도 제공된다고 가정하지 않는다. 플랫폼의 실제 제공 인터페이스와 운영 정책에 맞는 정정 어댑터를 별도 검증한다. 검증된 구매 정보 없이 관리자가 Robux 환불을 완료했다고 표시하지 않는다.

## 5. 채팅·초대·공개 연령

자유 채팅은 TextChatService와 현재 플랫폼 권한을 따른다. 역할 수락·가격 비교·약속 이행은 사전에 정의된 게임 행동으로 제공한다. 이를 플랫폼 채팅 제한을 우회하는 자유 문자열 전달 채널로 바꾸지 않는다. 현재 공식 문서는 플랫폼 통합 채팅이 켜진 경우 native 시스템 사용과 코드에서의 메시지 접근 제약을 설명한다. [R06]

목표 연령13+는 오픈타운의 기획 가정이다. Roblox에서 이 연령대가 바로 접근할 수 있다는 뜻은 아니다. 현재 공식 게시 체계는 16세 미만 이용자의 접근에 별도 요건과 평가 과정을 두므로, 공개 직전에 실제 소유 계정·콘텐츠 등급·대상 이용자 요건을 확인한다. [R07]

친구 초대와 서버 이동도 해당 플랫폼의 연결·권한을 사용한다. 다른 서버로 이동하기 전에 기존 스테이지의 경제 마감과 세션 소유권 이전을 처리한다. Teleport 도착 여부가 거래 성공의 유일한 증거가 되지 않도록 한다.

## 6. 재사용하는 것과 다시 만드는 것

| 유지 | 다시 구현·검증 |
|---|---|
| 네 업종 제품·작업 그래프·연구·선택 정의 | 장면·조작·GUI·애니메이션 |
| TC/DG/PB/XP의 의미 | 결제 진입·영수증·가격 표시 |
| 원가·운영비 예약과 경제 fixture | DataStore 처리량·복구·세션 잠금 |
| 시장 수요 보존·명성 관측 규칙 | 원격 통신·상태 뷰·접속 재개 |
| 스토리보드의 원인·선택·결과 | 화면 비율·카메라·사용자 입력 |
| T01~T24의 기대 결과 | 플랫폼별 오류 주입과 실기기 증빙 |

공통 fixture는 최종 TC·예약 잔액·선택 상태·고객 수·명성 관측 ID가 같아야 한다. 내부 코드나 렌더링 결과의 픽셀까지 같을 필요는 없다. 웹 MVP 일정에 이 대체 구현을 함께 넣지 않고 별도 이식 프로젝트로 산정한다.

## 7. 공식 근거

확인일: 2026-11-11. API·정책은 구현 및 공개 시 재확인한다.

- [R01 — Client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary): 원격 입력 검증.
- [R02 — GlobalDataStore](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore): UpdateAsync와 충돌 시 변환 재실행.
- [R03 — Player data and purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing): 한 키 저장, 세션 잠금, 로드 실패 대응.
- [R04 — Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores): 일시 데이터와 만료.
- [R05 — MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService): ProcessReceipt, BindReceiptHandler, 지급·재시도 동작.
- [R06 — Text chat overview](https://create.roblox.com/docs/chat/in-experience-text-chat): 플랫폼 채팅과 권한.
- [R07 — Roblox Kids and Select](https://create.roblox.com/docs/production/publishing/kids-and-select): 대상 연령별 게시·접근 요건.

## 연관 문서

- 현재 제작 대상: [Three.js 웹 구현](01-web-threejs.md)
- 규칙 원본: [공통 게임 구현 명세](../04-implementation/01-engine-neutral-spec.md)
- 경제 원본: [경제와 아이템](../01-game/06-economy-and-items.md)
