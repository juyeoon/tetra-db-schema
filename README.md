# db-schema

Tetra MVP의 DB 스키마 마이그레이션(Flyway). 발급 API · Portal · Console이 같은 RDS를 쓰므로 스키마는 이 저장소 한 곳에서 바꾼다.

| 폴더 | 스키마 | 적용 |
|---|---|---|
| `db/migration/platform/` | 공용 `tetra_platform` (tenant · operator · traffic_plan · template · event_registry …) | 이 저장소 CI (main → 수동 `flyway:migrate`) |
| `db/migration/tenant/` | 테넌트마다 `t_{tenant_id}` (event · 쿠폰 · 발급 이력 …) | **새 테넌트**: Console이 WF5(테넌트 가입)에서 Flyway 라이브러리로 생성 · **기존 테넌트 전부**: 이 저장소 CI가 `t_*`를 돌며 적용 |

## 규칙

- 파일 이름: `V<번호>__<소문자_설명>.sql` (예: `V2__add_coupon_expiry.sql`). 번호는 폴더마다 따로 1부터.
- **이미 merge된 파일은 고치거나 지우지 않는다.** Flyway가 체크섬으로 막는다. 바꿀 때는 새 버전 파일로(되돌리기도 새 파일로).
- 테넌트 파일에서 공용 테이블은 `tetra_platform.` 을 붙여 참조하고, 자기 테이블에는 스키마를 붙이지 않는다(실행 스키마에 생성).
- 공용(platform) 변경이 테넌트 파일보다 먼저 적용된다 — 테넌트 테이블이 공용 테이블을 FK로 참조하므로.
- 앱 시작 때 자동 마이그레이션은 쓰지 않는다(이벤트 Pod가 여러 개 동시에 뜬다). 예외는 Console의 새 테넌트 스키마 생성뿐.
- Console 이미지에는 `db/migration/tenant/`를 **같은 경로**(`classpath:db/migration/tenant`)로 넣는다. 이력 테이블은 기본 이름 `flyway_schema_history`, 스키마는 `schemas("t_{tenant_id}")`.

## 흐름

```
작업 브랜치 → MR (flyway:lint) → 리뷰 → merge
  → main 파이프라인: flyway:driver · flyway:tenants → flyway:info (미적용 목록 확인)
  → flyway:migrate ▶ (공용 → 테넌트 전부)
```

접속 계정은 `tetra_migrator`(DDL, `tetra_platform.*` · `` `t\_%`.* ``만). 비밀번호는 Secrets Manager `tetra/dev/db/migrator`가 원본이고, 이 프로젝트의 CI/CD 변수 `FLYWAY_PASSWORD`(Protected · Masked and hidden)에 복사해 둔다.

V1 두 파일은 DB 설계(`MVP/INFRA/PLAN&DATA/tetra_platform.sql` · `tenant_schema.sql`, 2026-10-16)의 사본이다.
