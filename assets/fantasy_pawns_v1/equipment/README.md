# 개별 장비 에셋

각 링크는 장비 하나만 들어 있는 투명 PNG다. 캐릭터·다른 장비는 포함하지 않는다.
갑옷과 투구는 각각 독립적으로 로드하고 위치를 맞춰 겹친다.

| 소재 | 갑옷 파일 | 투구 파일 |
|---|---|---|
| 천 | [cloth_armor.png](cloth_armor.png) | [cloth_helmet.png](cloth_helmet.png) |
| 가죽 | [leather.png](leather.png) | [leather_helmet.png](leather_helmet.png) |
| 누비 | [padded_armor.png](padded_armor.png) | [padded_helmet.png](padded_helmet.png) |
| 사슬 | [chain_armor.png](chain_armor.png) | [chain_helmet.png](chain_helmet.png) |
| 판금 | [plate_armor.png](plate_armor.png) | [iron_helmet.png](iron_helmet.png) |

종족별 위치 및 천 크기 보정은 `playtest/fantasy_equipment_overlays.gd`에서 처리한다.
몸통/머리의 선택 키는 각각 `armor_definition_id`/`head_definition_id`이다.
