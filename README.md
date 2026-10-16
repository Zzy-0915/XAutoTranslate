# XAutoTranslate v12：安装时部署依赖

目标：X 12.33（31），iOS 17.2 及以上 arm64 越狱设备。基于 v10 翻译核心，保留原插件设置中的自动翻译模块。

## v11 问题与修复

用户实机返回 `file system sandbox blocked mmap()`，明确阻止从应用数据容器加载 v11 释放的 libellekit.dylib。代码签名校验不能证明该路径允许执行。

v12 删除可执行库内嵌、运行时解压写入和 dlopen。主 dylib 通过 Mach-O 加载命令依赖同目录 BHTwitter.dylib 和 libbhFLEX.dylib；BHTwitter 依赖同目录 XATKit.dylib（原 ElleKit 的 arm64 文件，修正名称、依赖并临时签名）。使用唯一名称避免被注入器按通用 libellekit 文件名忽略。所有库必须由注入器在安装阶段部署到允许执行的位置，并分别完成所需签名处理；应用启动时不再生成或修改代码文件。

## 安装

1. 在 JailFools 的 X 条目移除 v11 和其他旧版 XAutoTranslate，避免重复注入。已独立注入的 BHTwitter/NFB 也先移除。
2. 完全退出 X。
3. 在 JailFools 中导入 **XAutoTranslate-v12-Inject.deb 完整注入包**。用户已确认其界面不接受 ZIP，因此提供 DEB；两者包含完全相同的四个 dylib 与 BHTwitter.bundle 资源。DEB 用于注入器导入，不通过 Sileo/包管理器安装到系统。
4. 注入器应将四个库放在同一可执行目录，并处理每个库的签名。资源可在 X.app 根目录，或与主 dylib 同目录。
5. 打开 X → 原插件设置 → 自动翻译。默认开启；总开关修改后重启 X 生效。

**不能只注入 XAutoTranslate-v12.dylib。** 它有必需的相邻动态库依赖；缺失依赖会导致应用在插件代码执行前加载失败。主 dylib 随附是为完整性检查或手动部署使用，完整 DEB 才是此次交付的注入文件。

DEB 使用标准 ar、control.tar.gz 和 data.tar.gz。布局参考 [TrollFools 公开预处理源码](https://github.com/Lessica/TrollFools/blob/main/TrollFools/InjectorV3%2BPreprocess.swift) 的 DEB 导入实现，显式保留 BHTwitter.bundle 目录条目并验证提取后的内容与已验证 ZIP 逐字节相同。不含维护脚本，也不改变翻译二进制逻辑。本机无法实测 JailFools 5.2.3 的导入结果；不要将依赖复制到应用数据目录后加载。

v11 在 Library/Application Support/XAutoTranslate/Integrated 下释放的旧文件不再被读取。本版不自动删除手机上的目录。

## 保留行为

可见推文、评论快速进入翻译队列；中文和无语言内容跳过。官方优先，确认原生失败后 Google GTX 补位；保留成功译文进程缓存、去重、串行并发限制、冷却与重试退避，使用 X 原生已翻译与显示原文界面。排队、超时或无效译文不冒充官方失败。翻译模块无实时日志、导出、手势模块；第三方原插件自带调试功能未修改。

Google 补位向 translate.googleapis.com 发送待翻译文本，不发送 X 凭证。GTX 非正式接口可能限流或不可用。

## 来源、构建与验证边界

第三方 BHTwitter、ElleKit、FLEX 及资源来自用户提供的 X_12.13_NFB.ipa，Vendor/manifest.json 记录原始文件摘要和分片完整性。保留原作者信息及 Acknowledgements.rtf。安装/侧载辅助 zxPluginsInject、sideloadFixerLol 不混入功能插件。

本仓库编译自有加载器入口、模块设置桥接和自动翻译源码；不声称恢复第三方源码或将多个预编译 Mach-O 静态合并成一个文件。第三方保留原编译代码，仅修正依赖和签名。原插件来自 X 12.13，全部功能在 X 12.33 上的兼容性仍需实机确认。

GitHub Actions 使用 Apple iPhoneOS SDK 编译、签名，验证原始文件摘要、四个 Mach-O 的签名页哈希、完整包依赖闭合、资源布局、无运行时可执行文件释放或 dlopen，并运行翻译回归测试。构建通过不证明 JailFools 已正确安装，也不代表设备已经成功加载。

运行 make 或 bash scripts/build-ios.sh，产物在 output。完整注入包仅包含需要部署的库与资源，不含源码、构建脚本或说明文件。
