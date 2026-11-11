# 데이터와 메시지 계약

버전 2.0 · 설계 기준 2026-11-11 · 상태: 구현 기준안  
[문서 트리](../README.md) / [구현 문서](README.md)

## 1. 읽는 순서와 원칙

먼저 [공통 구현 명세](01-engine-neutral-spec.md)를 읽는다. 아래 모델은 영구 데이터와 전송 데이터의 의미를 정의하며 저장 형식이나 프로그래밍 언어를 지정하지 않는다. 단위·상태명·버전·권위 주체를 생략한 필드는 구현에 넣지 않는다.

- 재화: 정수 TC·DG·PB. 소수 재화를 저장하는 대신 운영비의 잔여 초를 저장한다.
- 비율: 표시용 퍼센트와 계산용 정규화 값을 혼용하지 않는다. 계산 정밀도와 반올림 시점은 콘텐츠 버전에 고정한다.
- 좌표: 논리 격자 정수. 화면의 부동소수 좌표를 그대로 배치 데이터로 저장하지 않는다.
- 시간: 작업·약속은 자신의 `clockKind`와 만료 tick을 함께 저장한다.
- 식별자: 내부에서 발급한 불투명 문자열. 이름이나 화면 문구를 데이터 키로 쓰지 않는다.
- 예약 원가·이미 지출한 원가·매출을 각각 저장한다. 하나의 `profit` 숫자로 덮어쓰지 않는다.

## 2. 주요 데이터 모델

| 모델 | 필수 필드 | 일관성 경계·공개 범위 |
|---|---|---|
| PlayerProfile | playerId, schemaVersion, revision, activeBusinessId, startupGrantId, tutorialState, xp | 소유자 전용. 초기 지급과 사업 생성은 같은 경계. |
| Wallet | tcBalance, tcReservedMaterials, tcReservedOperating, dgBalance, revision | 소유자 전용. 예약액은 잔액을 초과하지 않음. |
| Business | businessId, ownerId, archetype, state, productVersion, facilityTier, activeWorkId, activeTick, feeAccumulatorSeconds | 개인 상세와 공개 요약을 분리. feeAccumulatorSeconds는 0~29. |
| Stage | stageId, contentVersion, ownerEpoch, stageTick, demandSequence, status, seats | 좌석·공개 시장만 공개. 무작위 생성 내부 상태는 비공개. |
| StageSeat | playerId, businessId, connectionState, graceDeadlineServerTime, graceOwnerEpoch, lastAcknowledgedRevision | 소유자와 운영자에게만 접속 복구 상세 공개. |
| Demand | demandId, origin, trainingMode?, needType, segmentId, budgetBand, state, selectedBusinessId, reservationId | 후보 평가 정보는 서버 전용. 사용자에게는 관찰 가능한 요구만 공개. |
| Order | orderId, demandId, offerVersion, state, workflowCursor, reservedCostTC, spentCostTC, grossTC, workDeadline, qualityEvidence | 소유자 상세. 다른 사용자에게 진행 수량·외관만 공개. |
| WorkItem | workId, kind, subtype?, sourceOrderId?, decisionInstanceId?, workflowCursor, state, latestFinishTick | 생산·연구·사건 대응의 공유 슬롯. kind=PRODUCTION/RESEARCH/EVENT_WORK. |
| Research | researchId, branchId, state, contentVersion, costTC, workProgress, verificationEvidence | 소유자 상세. 연구 결과 공개 여부는 제품 정책에 따름. |
| Reputation | businessId, dimensionValues, observationCount, lastObservationIds | 공적 명성 요약만 공개. 개별 고객의 내부 판단·숨은 난수 비공개. |
| DecisionInstance | instanceId, eventDefinitionId, definitionVersion, seedRef, state, optionId, choiceRevision, pendingEffectIds | 당사자 상세. 상대방 개인정보·영업비밀을 모델 입력으로 제공하지 않음. |
| Promise | promiseId, sourceId, state, clockKind, deadlineTick, evidenceRefs, resolutionId | 수행자에게 조건·기한·완료 근거 공개. |
| Project | projectId, attemptId, pbAllocated, pbReserved, pbSpent, contractVersion, state, rewardKey | PB는 이 프로젝트에서만 유효. 개인 TC와 구분. |
| InventoryItem | instanceId, catalogId, functionBaseId, ownerId, style, provenance, grantId | 전시 가능 속성과 개인 거래 이력을 분리. |
| Placement | placementId, itemInstanceId, plotId, cellX, cellY, rotationQuarter, layoutRevision | 공개 공간의 배치만 공개. 소유권 검증 후 적용. |
| LedgerEntry | ledgerId, ownerId, operationKey, asset, amount, reason, sourceId, reversalOf, commitRevision | 수정 불가. 정정은 반대 방향의 새 기록으로 남김. |
| CommandReceipt | actorId, commandId, payloadHash, status, result, committedRevision | 재시도 결과와 동일 입력 여부를 확인. |
| OutgoingEvent | eventId, aggregateId, revision, type, payload, deliveryState | 상태 변경과 함께 보존. 수신자가 중복을 제거. |

`tcReserved = tcReservedMaterials + tcReservedOperating`이며 소비 가능 TC는 `tcBalance - tcReserved`다. `tcReservedMaterials`에는 주문 원가와 아직 착수하지 않은 사건 대응의 직접비를 포함한다. 수요 수락 시 변동비와 별도로 현재·대기 업무의 최대 서비스 시간을 감당할 운영비를 예약하고, 착수 시 다시 확인한다. 예기치 않은 미납이나 음수 지갑을 만들지 않는다. 정확한 예약·정산 규칙은 [경제 문서](../01-game/06-economy-and-items.md)를 따른다.

### 수요 출처와 후속 작업

`Demand.origin`은 MARKET 또는 TRAINING이다. TRAINING의 `trainingMode=ONBOARDING`은 최초 업종 안내의 1회 거래로 기본 TC·XP를 정상 정산하고 반복 지급을 막는다. `trainingMode=PRACTICE`는 가상 지갑을 사용하며 영구 TC·DG·XP·명성·소유권을 바꾸지 않는다. 모든 TRAINING 수요는 경쟁 수요풀 밖에 있다.

DemandState는 CREATED/CONSIDERING/RESERVED/IN_SERVICE/COMPLETED/FAILED/OUTSIDE/ABANDONED다. 고객의 판단 상태이며 OrderState와 다르다. 고객이 OUTSIDE로 가면 매출은0이고, 주문이 생긴 뒤에는 해당 Order의 정산 결과와 고객 결과를 연결한다.

EVENT_WORK의 subtype=AFTERCARE는 납품 이후의 수정·지원이다. 원래 Order는 DELIVERED를 유지하며 sourceOrderId로만 연결한다. 소유자는 운영비 예약을 확인하고 CLOSED에서 CLOSING으로 전환해 후속 업무를 수행한 뒤 CLOSED로 돌아간다. 신규 수요는 받지 않고 추가 매출·XP·연구 완료를 지급하지 않는다. 자금이 부족하면 시간 연장이 없는 등록된 무료 해결 경로를 제공한다.

연결 복구 마감은 정상 서버의 실제 경과 시계로 판정한다. graceOwnerEpoch가 달라졌다면 이전 프로세스의 시계 값을 비교해 사용자 귀책 종료를 만들지 않고 서버 복구 절차를 적용한다.

## 3. 명령 봉투

```json
{
  "protocolVersion": 2,
  "commandId": "cmd_opaque_unique",
  "commandType": "ChooseOption",
  "stageId": "stage_opaque",
  "businessId": "business_opaque",
  "expectedRevision": 41,
  "contentVersion": "ot2-mvp-001",
  "payload": {
    "decisionInstanceId": "decision_opaque",
    "optionId": "OPT_REPAIR",
    "choiceRevision": 2
  }
}
```

사용자 신원은 인증 문맥에서 얻는다. `playerId`, 잔액, 보상량, 구매 실화폐 가격, 고객 평가 점수를 명령 payload의 권위 있는 값으로 받지 않는다. 같은 commandId의 재전달에는 최초 결과를 반환하고, payload가 달라졌으면 `COMMAND_CONFLICT`를 반환한다.

요청 크기의 초기 상한은 4 KiB다. 대량 배치 편집은 객체 수가 제한된 묶음과 `layoutRevision`을 사용한다. 클라이언트가 보내는 시간은 지연 관측에만 쓰며 작업 완료 시각으로 신뢰하지 않는다. 이동 입력은 별도 가벼운 문맥을 사용하고, 경제 명령 ID를 이동마다 영구 보관하지 않는다.

### 명령별 핵심 payload와 검증

| ID | 필수 payload | 추가 검증 |
|---|---|---|
| C01 | preferredStageId 또는 matchmakingPreference, inviteToken? | 초대 유효성, 좌석 6명, 사업 중복 접속 |
| C02 | archetype, approvedNameId 또는 이름 요청, starterStyleId | 업종 4종, 영구 사업·지원금 존재 여부 |
| C03 | openingPlan, promiseRevision | 과거 기한, 이미 확정된 주문과 충돌 |
| C04 | requestedState=OPEN | 소유권, 운영 자금, 필수 설비, 유효 제품 |
| C05 | productId, offerId, priceTC, offerRevision | 허용 가격 범위와 연구 해금, 기존 계약 불변 |
| C06 | demandId, offerRevision | 수요 호환, 미예약, 원가·운영비 예약 가능액, 예약 큐 한도 |
| C07 | workId, actionId, evidenceChoiceId? | 현재 단계의 허용 행동, 슬롯, 운영비 예약, 착수 중복 |
| C08 | orderId | READY 또는 승인된 완료 조건, 정상 검수 |
| C09 | researchDefinitionId | 연구 비용, 선행조건, 슬롯, 중복 연구 |
| C10 | researchInstanceId | READY, 적용 대상 버전, 이미 적용 여부 |
| C11 | assetInstanceId, actionId | 소유권, 설비 상태, 비용·시간 조건 |
| C12 | itemInstanceId, cellX, cellY, rotationQuarter, layoutRevision | 정수 격자, 허용 회전, 통로·필수 사용점 |
| C13 | catalogId, quoteVersion, quantity | 허용 화폐, 가격 재확인, 수량·소유 한도 |
| C14 | decisionInstanceId, optionId, choiceRevision | 아직 미선택, 최신 비용·운영비 추가 예약 조건, 지연 효과 ID |
| C15 | promiseId, actionId | 실제 작업·납품 근거, 수행자·기한 |
| C16 | mode=TRAINING_BUDGET, projectDefinitionId, contractId | 최초 연습 상태, PB120과 개인 지갑의 분리 |
| C17 | mode=FINISH 또는 CANCEL, affectedWorkIds, confirmationRevision | 취소 손실 예고와 실제 대상 일치 |
| C18 | closureRevision | 잔여 약속·정산 처리, 다른 세션 중복 |
| C19 | lastRevision, lastEventId | 자신의 비공개 뷰만 복원 |
| C20 | visibility, allowedVisitorPolicy | 소유자의 설정만 수정 |

WorkItem의 작업 상태는 QUEUED/RUNNING/WAITING_INPUT/DONE/CANCELLED다. WAITING_INPUT에도 유한한 기한이 있으며 해당 시간은 운영비 예약 계산에 포함한다. Order가 READY가 되거나 Research가 READY가 되면 작업 계산은 완료된 것으로 본다. 생산은 이어서 매출 정산을 시도하고, 연구는 적용 C10을 기다린다.

READY는 매출을 기다리며 무기한 방치하는 상태가 아니다. 조건이 완성되면 권위 실행자가 C08과 같은 전달 처리를 즉시 시도한다. 사용자의 선택이 필요한 검수는 IN_PROGRESS 안의 명시된 단계와 기한으로 표현한다. 화면의 전달 버튼은 같은 처리의 요청 수단이며 추가 보상을 발생시키지 않는다.

## 4. 응답과 오류

```json
{
  "commandId": "cmd_opaque_unique",
  "status": "COMMITTED",
  "committedRevision": 42,
  "resultType": "ChoiceCommitted",
  "result": {
    "decisionInstanceId": "decision_opaque",
    "optionId": "OPT_REPAIR",
    "pendingEffectIds": ["effect_opaque"]
  }
}
```

`RECEIVED`는 접수, `PENDING`은 영구 처리 중, `COMMITTED`는 저장 완료, `REJECTED`는 적용되지 않음을 뜻한다. 성공 연출은 COMMITTED 이후에 실행한다. 응답이 없으면 실패로 추정해 새 ID로 결제·보상을 재요청하지 않는다.

| 오류 코드 | 뜻 | 사용자 복구 |
|---|---|---|
| AUTH_REQUIRED | 인증 문맥 없음 | 재인증 후 결과 조회 |
| NOT_OWNER | 사업·아이템 소유자 불일치 | 조작 중단 |
| INVALID_PAYLOAD | 유형·범위·길이·유한수 실패 | 안전한 기본 입력 복원 |
| RATE_LIMITED | 요청 빈도 초과 | 재시도 대기 표시 |
| COMMAND_CONFLICT | 같은 ID에 다른 내용 | 기존 결과 조회, 새 의도는 새 ID |
| REVISION_CONFLICT | 읽은 상태가 오래됨 | 최신 상태와 비용 재표시 |
| CONTENT_VERSION_MISMATCH | 호환되지 않는 콘텐츠 | 해당 기록 버전 로드 또는 새 사건으로 안내 |
| STAGE_FULL | 좌석 없음 | 대기 또는 다른 상권 선택 |
| STALE_OWNER_EPOCH | 이전 실행자 요청 | 최신 스테이지로 재동기화 |
| BUSINESS_NOT_AVAILABLE | 영업·연결 조건 미충족 | 재개 또는 마감 안내 |
| DEMAND_ALREADY_RESERVED | 다른 업체가 예약함 | 다른 수요를 기다림, 재화 차감 없음 |
| INSUFFICIENT_AVAILABLE_TC | 예약액·운영비를 고려한 TC 부족 | 가격·작업 계획 수정 |
| SLOT_BUSY | 생산·연구 슬롯 점유 | 기존 작업 완료·취소 선택 |
| PRECONDITION_FAILED | 단계·품질·검수 조건 불충족 | 필요한 행동을 구체적으로 표시 |
| PATH_BLOCKED | 고객·작업자 통로 차단 | 미리보기 위치 복원 |
| STORAGE_UNAVAILABLE | 영구 확정 불가 | 소비·지급 잠금, 같은 ID 결과 조회 |
| RESYNC_REQUIRED | 상태 간격이 너무 큼 | 전체 스냅샷 적용 |
| TEXT_NOT_APPROVED | 공개 문구 처리 실패 | 승인된 기본 이름 사용 |

## 5. 원장과 거래 예시

일반 카페 주문 한 건, 시작 TC80, 다른 지출·사건이 없고 테스트 작업 정의의 최대 남은 유상 시간 H=30초인 fixture다. 단계별 결과를 독립적으로 검사한다. 실제 콘텐츠에 선택·검수 대기 상한이 더 있다면 그 시간을 H에 포함하므로 최초 예약액도 더 커질 수 있다.

| 순서 | 상태 | TC 잔액 | 예약 TC | 원가·매출 기록 |
|---|---|---:|---:|---|
| 0 | 주문 전 | 80 | 0 | 없음 |
| 1 | RESERVED | 80 | 7 | material hold=6 + operating hold=1, 아직 지출 아님 |
| 2 | IN_PROGRESS | 74 | 1 | material debit=6, operating hold=1 |
| 3 | 유상 운영 30초 누적 | 73 | 0 | operating debit=1 |
| 4 | DELIVERED | 89 | 0 | sale credit=16 |

정상 완료의 공헌이익은 10 TC, 이 fixture의 운영비 포함 순이익은 9 TC다. 전달 시간이 다른 고정비 구간에 걸치면 실제 정산값이 달라질 수 있다. 프로젝트·훈련 주문은 별도 정책이며 이 fixture를 자동 적용하지 않는다.

- 착수 전 취소: 총 hold 7 해제, 잔액 80 유지. 발생한 다른 운영비는 별도다.
- 착수 후 사용자 취소: 지출 6을 보존하고 매출 0. 표시된 취소 정책의 명성 결과를 한 번만 적용한다.
- 착수 후 서버 원인 실패: `reversalOf`로 원가 6 복구. 장애 구간 비용과 귀책 불이익은 적용하지 않는다.
- 전달 재요청: 같은 매출 operationKey가 이미 있으므로 기록·잔액 변화 없음.

권장 경제 작업 키는 `order/{orderId}/cost`, `order/{orderId}/sale`, `order/{orderId}/cancel`, `choice/{instanceId}/{effectId}`, `purchase/{provider}/{paymentId}/grant`처럼 의미별로 구분한다. 영구 구매·소유권에 연결된 중복 방지 키를 임의 시간 경과만으로 삭제하지 않는다.

## 6. 공개 상태와 개인 상태

공개 뷰에는 업종, 이름, 개장 상태, 외관, 공개 명성, 현재 혼잡도, 공개된 제안을 포함한다. 개인 뷰에는 TC·DG·PB, 원가, 예약액, 진행 중 연구, 비공개 선택, 계약 세부 조건을 포함한다. 내부 뷰에는 고객 효용의 숨은 가중치, 무작위 상태, 결제 증빙, 보안·운영 로그를 포함한다.

상대방의 개인 뷰를 먼저 전송하고 화면에서 숨기는 방식은 금지한다. 방문 허용은 편집 허용과 다르다. 스테이지를 떠나거나 공개 범위가 바뀌면 더 이상 볼 수 없는 객체를 해당 사용자의 뷰에서 제거한다.

## 7. 버전과 마이그레이션

각 프로필에는 schemaVersion, 각 콘텐츠 기록에는 definitionVersion, 각 명령에는 protocolVersion을 둔다. 저장 모델 변경은 작은 순차 변환으로 시행하고 이전 버전 fixture와 실패 복구 fixture를 유지한다.

진행 중 주문은 수락 당시 가격과 제품 버전을 유지한다. 진행 중 선택은 제시된 사건 버전과 확정한 optionId를 유지한다. 콘텐츠 교체로 선행 조건이 사라지면 임의로 실패 처리하지 않고 호환 처리기를 거쳐 해금·비용 복구·안내 중 정해진 전이를 적용한다.

로드 실패와 ‘아직 생성되지 않은 계정’을 구분한다. 데이터를 읽지 못했다고 초기80TC 프로필로 저장하지 않는다. 백업 복원은 지급 이력·구매 이력·중복 방지 기록도 함께 검토하며, 복원 이후 실제 지급된 거래를 다시 실행하지 않는다.

## 연관 문서

- 이전: [공통 게임 구현 명세](01-engine-neutral-spec.md)
- 다음: [실시간 동기화와 영구 저장](03-realtime-and-persistence.md)
- 데이터 원본: [경제와 아이템](../01-game/06-economy-and-items.md)
- 입력 콘텐츠: [콘텐츠 제작 규격](05-content-authoring.md)
