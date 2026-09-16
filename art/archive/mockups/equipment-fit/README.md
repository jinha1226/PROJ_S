# 다리 없는 인간 장비 착용 목업

사용자 결정: 다리를 추가하지 않고 기존 폰 베이스를 유지한다.

- `human-leather-helmet.png`: 1 기본 베이스 / 2 가죽갑옷 / 3 가죽갑옷과 철투구.
- `native-size.png`: 생성된 비교 목업의 캐릭터를 잘라 128px와 40px 캔버스에 맞춘 가독성 참고. 게임 캡처가 아니며, 엔진에서 정확한 레이어 정합을 검증한 결과는 아니다.
- 현재 캐릭터 런타임, 장비 슬롯, 장착 로직은 변경하지 않았다. 실제 장착 연동 시 동일 캔버스 기준 갑옷·투구 레이어 분리와 머리카락 마스킹이 필요하다.

내장 image_gen을 사용했다. 참조는 `assets/fantasy_pawns_v1/species/human.png`, `items/armor.png`, `items/helmet.png`이다.

## 최종 프롬프트

Use case: precise-object-edit, character equipment try-on mockup. Image 1 is the EXACT approved legless human pawn base. Image 2 is the existing leather armor design. Image 3 is the existing iron helmet design. Create one clean side-by-side comparison board with THREE large characters on flat muted slate gray background: 1 the unchanged human base; 2 that same human wearing only the brown leather armor from image 2; 3 that same human wearing BOTH that leather armor and the iron helmet from image 3. IMPORTANT: retain the short legless pawn silhouette, round large head, SAME overall height and body proportions, head center and shoulder position in all three columns. NO LEGS, NO FEET, NO HANDS, NO WEAPONS, no invented eyes or facial features. The outfit must be drawn fitted to this exact body: leather breastplate covers the gray tunic, small shoulder sections follow existing shoulders, belt sits at the lower torso. Helmet fits tightly around the existing round head, fully hides the hair, and follows image 3's simple light-gray rounded dome, dark T-shaped eye opening and short nose guard. Do not make the character taller or realistic. Match the existing game art's dark rounded contour and sparse two-tone shading exactly. Center the three versions with equal scale and baseline. Labels only digits 1, 2, 3 below the figures. No text otherwise. This is a try-on design preview, not a new character style. Keep all images crisp and simple enough to read as 40px sprites.
