# AnnoRead 阿诺阅读

AnnoRead 是面向 Anbernic RG CubeXX（muOS、720×720 屏幕）的 LÖVE / LuaJIT 阅读器，支持 Legado 格式书源、搜索、目录、正文阅读、书架、章节缓存和 MiMo 语音朗读。

## 书源

公开仓库不包含可用的第三方书源。应用会扫描 `assets/sources/*.json` 和 `sources/*.json`，合并多个 Legado 格式的书源，并按 `bookSourceUrl` 去重。可将自己的书源 JSON 放进项目根目录的 `sources/`；掌机安装后也可放进应用目录下的 `sources/`。启动应用或打开书源管理页时会重新扫描。

[书源示例](examples/book_source.example.json) 是格式正确但指向 `example.invalid` 的不可用配置。复制为 `sources/my_source.json` 后，需要替换站点 URL、搜索/目录/正文规则并自行验证。支持单个书源对象、书源数组，以及带 `data` 或 `list` 数组的导出格式。书源停用状态和阅读数据保存在 LÖVE 用户数据目录。

## MiMo TTS

复制 [TTS 配置示例](config/mimo_tts.example.json) 为 `config/mimo_tts.json`，将 `api_key` 改成自己的 MiMo Key。示例中的 `YOUR_MIMO_API_KEY` 不能用于请求，真实配置已被 Git 忽略。

| 字段 | 说明 |
| --- | --- |
| `api_key` | MiMo API Key；也可通过 `MIMO_TTS_API_KEY` 环境变量提供。 |
| `voice` | MiMo 预置音色 ID，默认 `茉莉`。 |
| `voice_style` | 自然语言音色提示词；默认是清冷、干净的青年女声。 |
| `speed` | 相对语速，范围 `0.5`–`2.0`，默认 `1.12`（稍快）。 |
| `pitch` | 相对音高，整数 `-2` 到 `2`，默认 `-1`（略低）。 |

应用先读取随包的 `config/mimo_tts.json`，再读取 LÖVE 保存目录中的 `mimo_tts.json`，最后应用环境变量中的 Key。修改配置后重启应用。语速和音高会作为自然语言要求发送给模型，因此是相对目标，不保证精确倍速或半音值。详情见 [MiMo-V2.5-TTS 文档](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/multimodal-understanding/speech-synthesis-v2.5)。

本地打包时，如果 `config/mimo_tts.json` 存在，`make package` 会把它放入安装包。发布安装包前请检查其中是否含有自己的 Key。

## 构建与测试

项目需要 `gcc`、`make`、`cmake`、`python3`、`xxd`、`tar`、`xz`、`sha256sum`、Lua 5.1 兼容运行时（`lua`、`luac`、`luajit`）。`make run` 需要本机安装 LÖVE；掌机交叉构建还需要 `aarch64-linux-gnu-gcc`。仓库包含所需的 QuickJS 源码、固定版本的 libxml2 源码归档和 muOS 运行时文件。

```bash
make test       # 构建本机规则引擎并运行离线测试
make run        # 本机预览（需要 LÖVE）
make cross      # 交叉编译 AArch64 规则引擎
make package    # 测试、交叉编译并生成 dist/AnnoRead.muxapp
```

将 `.muxapp` 复制到 SD 卡的 `ARCHIVE` 目录，再通过 muOS Archive Manager 安装。用户数据位于 `<应用目录>/conf/love/rgcubexx-game/`；实际路径以 `love.filesystem.getSaveDirectory()` 返回值为准。构建及测试只验证主机和模拟环境，仍需在真实 RG CubeXX 上检查操作与显示。

规则引擎构建细节见 [engine/BUILDING.md](engine/BUILDING.md)。

随包组件的版权与许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
