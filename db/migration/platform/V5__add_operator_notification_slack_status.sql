-- =====================================================================
-- 운영자 알림 Slack 발송 상태 (2026-11-02, Slack 발송 조사 · 결정 11-02)
--  - Console 이 10초마다 PENDING 행을 찾아 Slack(chat.postMessage)으로 보낸다. Portal 이 넣은 행도 같다.
--  - 새 열은 모두 기본값이 있다. Portal 엔티티는 이 열들을 모르므로(V4 dedupe_key 도 모름) INSERT 에 넣지 않는다.
--  - 상태: PENDING(보낼 것 · 재시도 대기) → SENDING(한 태스크가 선점) → SENT · FAILED · UNKNOWN
--          UNKNOWN 은 보냈는지 모르는 행(응답 시간 초과 등). 다시 보내지 않는다 — URGENT 만 한 번 더 '재전송'으로 보낸다.
--          SKIPPED 는 보내지 않을 행(이 파일 적용 때 있던 행 · 켠 뒤 한 번도 시도하지 않고 오래된 행 · 채널 없음).
--  - 이 파일을 적용할 때 있던 행은 SKIPPED(slack_error = 'BEFORE_V5') — 과거 알림은 보내지 않는다.
--  - 보낸 채널 · 메시지 ts(slack_channel · slack_ts)를 남긴다. 메시지 수정 · 스레드 댓글에 둘 다 필요하고,
--    채널 설정(우선순위 → 채널)이 나중에 바뀌어도 원래 메시지를 찾을 수 있게 채널도 행에 저장한다.
--  - CHECK 추가는 온라인 DDL(INPLACE)이 되지 않아(기존 행을 검사하므로) ALGORITHM=COPY, LOCK=SHARED 다.
--    표를 복사하는 동안 읽기는 되고, 쓰기(알림 INSERT · 읽음 표시)는 복사가 끝날 때까지 기다린다.
--    열 · CHECK · 인덱스를 한 문장으로 묶어 복사는 한 번이고 원자적이다(실패하면 아무것도 바뀌지 않는다).
-- 재실행 안전 아님: MySQL 에는 ADD COLUMN IF NOT EXISTS 가 없다. ALTER 가 실패하면 flyway repair 후 다시 migrate.
--   UPDATE 만 실패하면 ALTER 는 남아 있으므로 열 · CHECK · 인덱스를 지운 뒤 repair · migrate
-- =====================================================================

-- 메타데이터 잠금(MDL)을 10초까지만 기다리고 실패한다. 기본값(1년)이면 긴 트랜잭션 뒤에서
-- ALTER 가 기다리는 동안 이 테이블을 쓰는 다른 쿼리까지 그 뒤에 줄줄이 막힌다.
SET SESSION lock_wait_timeout = 10;

ALTER TABLE operator_notification
    ADD COLUMN slack_status   VARCHAR(20)      NOT NULL DEFAULT 'PENDING'
        COMMENT 'Slack발송상태',
    ADD COLUMN slack_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT 'Slack시도횟수(429 제외)',
    ADD COLUMN slack_next_at  DATETIME         NULL     DEFAULT NULL
        COMMENT 'Slack다음시도일시. PENDING은 다음 시도 가능 일시(NULL이면 바로), SENDING은 선점 만료 일시',
    ADD COLUMN slack_sent_at  DATETIME         NULL     DEFAULT NULL
        COMMENT 'Slack발송일시',
    ADD COLUMN slack_error    VARCHAR(100)     NULL     DEFAULT NULL
        COMMENT 'Slack오류코드. 마지막 실패·건너뜀 원인(Slack error · HTTP 상태 · 예외 종류만, 응답 본문 없음)',
    ADD COLUMN slack_channel  VARCHAR(20)      CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL
        COMMENT 'Slack채널ID(보낸 채널). 보내지 않았으면 NULL',
    ADD COLUMN slack_ts       VARCHAR(32)      CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL
        COMMENT 'Slack메시지ts(chat.postMessage 응답). 보내지 않았으면 NULL',
    ADD CONSTRAINT chk_operator_notif_slack_status
        CHECK (slack_status IN ('PENDING','SENDING','SENT','FAILED','SKIPPED','UNKNOWN')),
    ADD INDEX idx_operator_notif_slack (slack_status, slack_next_at),   -- Slack 발송 작업(보낼 행 · 오래된 행 · 멈춘 선점)
    ALGORITHM=COPY, LOCK=SHARED;

-- 적용 때 있던 행은 보내지 않는다. ALTER 와 따로 커밋된다 — 이 UPDATE 가 빠져도 Console 의
-- '켠 뒤 한 번도 시도하지 않은 오래된 PENDING → SKIPPED'(기본 10분)가 과거 알림을 막는다.
UPDATE operator_notification SET slack_status = 'SKIPPED', slack_error = 'BEFORE_V5' WHERE slack_status = 'PENDING';
