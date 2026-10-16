# XAutoTranslate v11 + NFB/BHTwitter

面向 X 12.33（31）、iOS 17.2 及以上 arm64 越狱设备的单文件注入整合版。

从用户提供的 X_12.13_NFB.ipa 提取 BHTwitter、ElleKit、FLEX 的 arm64 代码及 BHTwitter.bundle。保留第三方原编译代码和资源，通过统一加载器封装在一个 dylib 中；不声称恢复或重新编译了第三方源码。单个 dylib 内是压缩后的已签名依赖与资源，不是将不同动态库直接拼接成一个 Mach-O 镜像。

## 使用

删除旧版 XAutoTranslate 与另行注入的 BHTwitter/NFB，然后彻底退出 X，在 JailFools 中只注入 XAutoTranslate-v11.dylib。不要同时安装 v9/v10/v11。

首次启动会把内置依赖释放至应用容器 Library/Application Support/XAutoTranslate/Integrated/<内容摘要>/，后续校验后复用，不需要联网下载依赖。保留签名并按 ElleKit、FLEX、BHTwitter 的顺序加载；BHTwitter 的 ElleKit 路径改为 @loader_path。iOS 必须允许加载这些临时签名的嵌入库；单文件注入成功不等于内层 dlopen 必定获准。加载失败会显示一次错误提示，独立自动翻译仍尝试启动。

打开原插件设置，在功能列表中选择“自动翻译”。默认开启；修改总开关后完全退出并重开 X。关闭时不安装自动翻译 hooks。启用时关闭原插件另一个自定义 API 翻译入口，避免两个翻译器竞争。

自动翻译保留 v10 行为：可见推文和评论快速排队、中文跳过、官方优先、确认官方失败后 Google GTX 补位、成功译文进程缓存、去重、并发限制、冷却与重试退避，使用 X 原生译文提示。不增加翻译日志、导出或手势模块。第三方原插件自带的调试功能与输出未修改。

Google 补位会将待翻译文本发送至 translate.googleapis.com，不发送 X 凭证；非正式 GTX 接口可能限流或不可用。

## 来源与验证范围

Vendor/manifest.json 记录原 IPA 摘要、归档和每个文件的摘要。Vendor/*.b64 是按顺序分片的 ZIP 编码，构建严格验证并还原。保留原 BHTwitter.bundle/Acknowledgements.rtf 与原作者界面信息。IPA 中的 zxPluginsInject 和 sideloadFixerLol 是安装/侧载辅助库，不并入功能插件，避免改动正常越狱 X 的签名与身份处理。此仓库只编译自有加载器、设置桥接和自动翻译源码，第三方库保留已编译字节，仅修正依赖路径并重新临时签名。

GitHub Actions 使用 Apple iPhoneOS SDK 编译签名，运行模拟翻译回归、资源完整性、嵌套签名页哈希及加载依赖检查。单文件可独立解析出全部内置依赖。原插件取自 X 12.13，不能凭静态检查保证全部原功能兼容 X 12.33；本整合版仍需在设备上验证原插件功能、设置入口、动态库加载权限和自动翻译共存。

构建：make 或 bash scripts/build-ios.sh；产物位于 output。tests、分片与脚本不会作为独立文件交给用户注入。
