# NOTICE — 외부 프로젝트와 출처

작은 빛은 아래 프로젝트와 자료를 사용하거나 참고합니다.
이 저장소와 릴리즈에는 아래 외부 프로그램의 코드나 바이너리가 **포함되어 있지 않습니다**.
각 프로그램은 사용자가 따로 설치하며, 각자의 라이선스를 따릅니다.

## 외부 프로그램 (별도 설치, 미포함)

| 프로젝트 | 용도 | 라이선스 | 출처 |
|---|---|---|---|
| agent-desktop (Vercel Labs) | 다른 앱 화면 읽기·클릭·입력 (접근성 API) | Apache-2.0 | https://github.com/vercel-labs/agent-desktop |
| Ollama | 로컬 LLM 실행 서버 | MIT | https://github.com/ollama/ollama |
| Qwen3 (qwen3:8b) | 기본 대화 모델 | Apache-2.0 | https://ollama.com/library/qwen3 |
| Claude Code (Anthropic) | 로컬이 대답하지 못할 때 대신 대답 (`claude -p`) | Anthropic 이용약관 | https://docs.claude.com/en/docs/claude-code |

- agent-desktop은 포크하거나 수정하지 않았습니다. 작은 빛은 설치된 `agent-desktop` CLI를 별도 프로세스로 실행해
  그 JSON 출력만 사용합니다(`mac/main.swift`의 `Desktop`). agent-desktop의 저작권은 Vercel Labs에 있습니다.
- Ollama와 Qwen3도 수정 없이 로컬 HTTP API(`/api/chat`, `/api/tags`)로만 사용합니다.
- Claude Code는 사용자가 설치하고 claude.ai 계정으로 로그인한 `claude` CLI를 그대로 실행합니다. Claude 대답은 그 계정의 사용 한도(Pro 등)에서 차감됩니다.

## 참고 자료

- **나무위키** '데스티니 시리즈', '데스티니 시리즈/스토리', '고스트(데스티니 시리즈)', '데스티니 가디언즈'와
  그 하위 문서(최후의 형체, 운명의 경계, 저항자). 2026년 11월 열람.
  `lore.js`의 세계관 내용은 이 문서들을 참고해 **사실만 요약하고 새로 서술**했으며, 원문 문장은 옮기지 않았습니다.
  나무위키 문서는 CC BY-NC-SA 2.0 KR 라이선스를 따릅니다.

## 상표·저작권

- **Destiny(데스티니)**, 수호자, 고스트, 여행자 등 관련 명칭과 세계관은 **Bungie, Inc.**의 상표 및 저작물입니다.
- 작은 빛은 **비공식 팬 프로젝트**이며 Bungie와 아무 관련이 없고, Bungie의 승인이나 후원을 받지 않았습니다.
- 앱의 대사, UI, 코어 그래픽은 이 프로젝트를 위해 새로 만들었으며 게임의 원문 대사, 음성, 이미지, 에셋을 포함하지 않습니다.
