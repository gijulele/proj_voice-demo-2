# vocalfit — 오늘 범위 스펙

## 한 문장 정의

로그인한 사용자가 자신의 십팔번을 30초 무반주로 불러서, 자기 음역대 판정 결과와 그 곡을 편하게 부를 수 있는 추천 키를 얻는다.

## 화면

1. 가입/로그인 — 이메일과 비밀번호를 입력해 계정을 만들고 들어온다
2. 십팔번 입력 — 오늘 부를 곡 제목을 고르고 녹음 안내를 읽는다
3. 녹음 — 무반주로 30초 부르고 다시 들어본 뒤 제출한다
4. 분석 대기 — 처리 진행 상태를 보며 기다리고, 실패하면 재녹음으로 돌아간다
5. 결과 — 내 음역대 그래프와 안전 최고음, 이 곡 추천 키(±n)를 확인하고 기록에 남긴다

## 데이터

1. users — id, email, password_hash, nickname, created_at
2. recordings — id, user_id, song_title, file_path, duration_sec, sample_rate, created_at
3. analyses — id, user_id, recording_id, status, low_note, high_note, safe_high_note, break_note, confidence, f0_series_path, error_message, created_at
4. key_results — id, user_id, analysis_id, song_ref_id, recommended_key_shift, verdict, created_at
5. song_refs — id, song_title, artist, ref_high_note, ref_low_note, source (프리셋 10곡 수동 시드, 사용자 생성 데이터가 아니라 user_id 없음)

## 오늘 만들 기능 3개

1. 이메일과 비밀번호로 가입하고 로그인한다
2. 30초 무반주 녹음을 올려 최저음·안전 최고음·무너지는 지점을 뽑는다
3. 뽑은 음역대를 곡 기준음과 비교해 추천 키를 계산하고 내 기록에 저장한다

## 오늘 안 만들 것

### 1. DGX Spark 온프렘에서 오늘 못 돌리는 것 — 대체제

- Demucs 원곡 보컬 분리 → 프리셋 10곡의 최고음/최저음을 수동 입력한 song_refs 테이블로 대체
- Whisper 가사 단어 정렬 → 무반주 30초 입력으로 원곡 시간축 정렬 자체를 제거
- SwiftF0 + pYIN + Autocorrelation 3중 교차검증 → librosa pYIN 단일 추출 + 유성음 구간 백분위 컷(상위 5% 제외), CPU 처리
- 모델 Lazy Load/Unload, 청킹, FP16, 순차 큐 → 분석만 백그라운드 작업 1개로 처리, 큐 전환 자리만 확보

### 2. 2단 소리 데모 생성

- 포먼트 보존 피치시프트 (시간이 남을 경우의 옵션)
- SoulX-Singer 기반 제로샷 SVC 가창 데모 (다음 스프린트)

### 3. 노래방 번호 조회

- Manana Karaoke API 연동 — 결과 화면에 자리만 확보
