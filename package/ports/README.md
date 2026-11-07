# AnnoRead：PortMaster 试用包

本包仅新增 Ports 启动和打包能力，保留原来的 720×720 布局、原生手柄操作、应用内虚拟键盘和拼音输入法。没有接入外部虚拟键盘，也未适配其他分辨率。

## 运行条件

- AArch64 Linux、GLIBC 2.38 或更高。当前引擎仍采用现有 muOS 构建基线，不能据此宣称支持所有 PortMaster 固件。
- 已安装并更新 PortMaster，以及其 `love_11.5` 运行时。包内不重复附带 LÖVE；离线设备须预先安装运行时。
- 系统提供 curl 7.75 或更高，支持 HTTPS、`--compressed`，并有可用 CA 证书。
- 未进行掌机实测；优先在原来成功运行的 RG CubeXX / muOS 上验证。

## 安装

优先将 `annoread.zip` 放到 PortMaster 的 `autoinstall` 目录，打开 PortMaster 完成安装；安装目录因固件而异。muOS 通常为 `/mmc/MUOS/PortMaster/autoinstall/`。

手动安装时，`annoread/` 放入固件实际的数据 `ports` 目录，`AnnoRead.sh` 放入 Ports 菜单脚本目录。两者在 muOS 上可能不同，请沿用设备上其他 PortMaster 游戏的布局。启动器使用 PortMaster 提供的 `$directory` 定位 `/$directory/ports/annoread`，并非按脚本所在目录查找。

将自己的 Legado 书源 JSON 放到 `annoread/sources/`。包内不包含个人书源、个人 API Key、书架或缓存。

MiMo 听书：复制 `annoread/config/mimo_tts.example.json` 为 `annoread/config/mimo_tts.json` 后填入自己的 Key，或在首次运行后把 `mimo_tts.json` 放入下面的用户数据目录。保存目录中的配置优先，环境变量 `MIMO_TTS_API_KEY` 优先级最高。

## 输入与数据

- 使用原有应用内虚拟键盘和拼音候选，按键逻辑保持 `src/input.lua` 不变。
- 使用 PortMaster 的 SDL 手柄映射；gptokeyb 仅提供紧急退出，不映射日常按键，不启用外部键盘。
- 正常退出优先使用应用菜单或应用原有的长按 Start + Select。系统紧急退出可能先终止进程，不能保证经过应用保存流程。
- 用户数据：`annoread/conf/love/rgcubexx-game/`。更新包不包含 `conf/`，请保留该目录。
- 从 `.muxapp` 迁移时，在应用退出后将原应用的 `conf/` 复制到 `annoread/conf/`；如需保留根目录书源和 TTS 配置，也需单独复制。不要覆盖已有数据而不备份。
- muOS 上保留原有临时延长闲置超时的行为，并在正常退出时恢复。其他固件的防休眠未适配。

## 排查与构建

启动日志位于 `annoread/log.txt`，引擎构建信息位于 `annoread/build-info.json`。缺少运行时、架构不符或检测到旧 GLIBC/curl 时，启动器会在日志中解释原因。

在项目根目录运行 `make package-ports`，执行离线测试、AArch64 交叉构建并生成 `dist/annoread.zip`。需要现有构建依赖及 `readelf`。打包器只选择发布所需资源，始终排除本地真实 TTS 配置、书源 JSON 与用户数据。

这是可安装的本地试用包，不是官方目录上架完成品。正式提交还需设备验收、截图、gameinfo.xml 和维护者信息。
