# XAutoTranslate v4 · Apple SDK 构建版

目标为 X 12.33（31）、iOS 17.2.1、arm64，供 JailFools 注入。中文跳过，非中文帖子/评论通过 X 自身的翻译事件与语言设置路径处理。真实覆盖范围与请求成功情况需设备验证，不能保证所有语种或评论均已修复。

## 构建

Actions 的 **Build XAutoTranslate with Apple SDK** 在 macOS 上使用 Xcode/iPhoneOS SDK 编译、codesign 签名并核验 dylib，产物在对应运行的 Artifacts 中。根目录不再保留另一份不参与构建的 Tweak.x，workflow 也不再内嵌生成另外的源码。

本地需 Mac + Xcode，执行 `make` 或 `bash scripts/build-ios.sh`。产物为 `output/XAutoTranslate-v4.dylib`，附带 `build-info.txt`（提交 SHA、Xcode/SDK/Clang 版本及文件 SHA-256）。不会生成 deb。

## 安装与日志按钮

1. 在 JailFools 的 X 条目中移除先前注入的本插件旧版，不必卸载 X 或移除无关插件。
2. 注入 **XAutoTranslate-v4.dylib**，完全退出并重开 X。不要同时加载多个版本。
3. 点击屏幕右侧中部的蓝色 **日志** 按钮，打开 **实时日志 / 导出日志**。没有双指长按入口。
4. 复现未翻译的帖子和评论后导出日志；关闭面板后仍持续记录，不会自动上传。

按钮和文件日志都需要动态库实际加载。C 构造函数与原生 Objective-C `+load` 均调用一个原子保护的初始化入口，只安装一次。`OBJC_LOAD_ENTER` 和 `CONSTRUCTOR_ENTER` 引导阶段帮助判断加载是否到达代码；新增 ObjC 入口并不证明之前失败的根因就是构造函数。

引导日志按进程 HOME/CFFIXED_USER_HOME/TMPDIR 尝试写入 X 数据容器根目录、Documents、tmp 下的 `XAutoTranslate-bootstrap.log`，构建标记为 `v4`。常规文件为 `Library/Caches/XAutoTranslate/current.log`；路径可能因环境与写权限不同而失败。没有按钮或新记录时，仍需核对注入器列表、实际 dylib 文件和设备系统日志。

## 源码

- `Sources/XAutoTranslate.c`：原生翻译路径、去重/限量观察和诊断事件；不额外请求第三方翻译服务。
- `Sources/XDiagnostics.c/h`：可移除的日志按钮、面板、导出和引导日志。
- `Sources/AppleBootstrap.m`：标准 Apple ObjC SDK 编译的 `+load` 入口。
- `scripts/build-ios.sh`、`scripts/verify-dylib.py`：唯一构建路径及产物结构/签名检查。

日志包含加载、Hook、语言、翻译触发/跳过、请求/缓存状态与原生显示条件。不记录帖子/译文正文、账号标识、Cookie 或令牌。原生操作结束不等于服务器保存成功，译文缓存状态不等于屏幕已显示。内存上限 512 KiB，常规文件上限 2 MiB，保留一个前段/前次文件；引导文件约 128 KiB 上限。

临时诊断可用 `XAD_DIAGNOSTICS=0 make` 编译关闭；Actions 同时检查该配置。问题全部解决后应删除诊断模块与核心诊断调用，恢复精简最终源码。

## 验证边界

构建通过只证明 Apple 工具链能够生成、签名并核验文件，不等于 JailFools 已加载，更不等于在 iPhone 上验证了所有翻译行为。真实设备上仍需根据日志继续定位。
