# 콘텐츠 JSON 편집 규칙

종족 성장, 이능, 아이템, 무기, 숙련 데이터의 원본은 이 폴더의 JSON 파일이다.
Godot 코드는 이 파일을 읽고 유효성 및 파일 사이의 참조를 검사한다.

## 파일 구분

- `growth_builds.json`: 능력치, 종족 고정 특성·분기, 이능, 접사 빌드 효과
- `items.json`: 장비·소모품과 접사
- `weapons.json`: 무기 전투 수치와 사용 숙련 ID
- `proficiencies.json`: 숙련/스킬 ID와 표시 이름

## 수정 원칙

1. `*_id`는 저장 파일과 다른 JSON에서 참조하는 영구 ID다. 출시 후에는 이름을
   바꾸거나 재사용하지 않는다. 화면에 보이는 이름은 `label`만 수정한다.
2. JSON을 수정할 때 해당 파일의 `content_version`도 함께 올린다.
   `content_schema_version`은 로더 형식이 바뀔 때만 코드와 함께 올린다.
3. 효과는 기존 `trigger`, `bonuses`, `required_item_tags`, `side_effect_ids` 구조와
   허용 목록 안에서 작성한다. 새 계산식이나 실행 훅은 JSON 문자열만 추가하지 말고
   먼저 코드에 안전한 구현과 검증을 추가한다.
4. 무기 아이템의 `weapon_id`는 `weapons.json`에, 무기의 `proficiency_id`는
   `proficiencies.json`에 존재해야 한다. 성장 접사의 `affix_id`는 `items.json`의
   접사와 일치해야 한다.
5. 저장 데이터에는 JSON 행 전체가 아니라 영구 ID와 플레이어의 선택/진행도만 남긴다.
   따라서 밸런스 수치 수정은 기존 저장에 반영되며, ID 변경은 별도 마이그레이션이
   필요하다.

## 편집 후 검사

프로젝트 루트에서 다음 두 검사를 실행한다.

```bash
jq empty data/content/*.json
godot --headless --path . --script res://tests/run_json_content_database_tests.gd
```

검사가 실패하면 잘못된 키, 중복 ID, 알 수 없는 참조를 먼저 수정한다. 게임 세션도
같은 통합 검증을 시작 시 실행하므로 깨진 콘텐츠로는 월드를 생성하지 않는다.
