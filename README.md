# XAutoTranslate v7 · 原生翻译显示修复

适用 X 12.33（31）、iOS 17.2+、arm64。使用 Apple iPhoneOS SDK 编译并进行 ad-hoc 签名。安装前移除旧版 XAutoTranslate，再通过 JailFools 注入本版本，彻底退出 X 后重新打开。旧进程中的 v6 错误缓存随退出清除。

## 本次修复

v6 错误地从官方译文包装器的 representedStatus 取回原文，随后将原文存成成功译文；本次直接读取 T1TranslatedStatusViewModel.translation.translation，验证目标语言为中文，并拒绝仅有空白/大小写变化的原文结果。成功状态不再根据原生 state 值单独判定。

移除插件的“语种 已翻译”正文前缀、低层 TFNTwitterStatus 文本模型替换和临时正文代理。官方译文保留原生翻译对象；Google 结果构建 TFSTwitterTranslation 与 T1TranslatedStatusViewModel，注册到 T1PostTranslationHelper 的翻译状态。两通道均使用 X 原有的译文正文、提示、服务商标识、显示原文和布局路径。Google 结果使用 X 自己的 Google 服务商对象，不冒充 Grok。

补齐原生通知使用的动态内容更新标记，通知当前列表/评论的原始视图模型重新生成文本和布局，而不是只调用 setNeedsLayout。写入翻译状态前后均核对原生译文包装器的 text 是否等于缓存译文。日志中的 native wrapper verified 表示模型文字核对通过，并不等于已读取屏幕像素。实际手机显示效果仍需实机验证。

开启原生行内翻译布局，并统一已核对的正文/提示显示条件，避免详情页能显示而列表仍选中原文。只有通过验证的译文缓存能打开对应原生显示分支；显示原文时保留原生切换状态。流式中间状态不作为完整译文写入成功缓存。

## 翻译策略

官方优先，官方失败或 8 秒超时自动转 Google。官方失败后暂停 5 分钟，暂停期间新内容直接走 Google；到期只允许一条探测，成功恢复官方优先，失败延长暂停，最长 15 分钟。已在途的官方任务没有已核对的安全取消接口，可能在切换后结束；缓存保留第一个通过验证的成功结果。中文跳过，未完成或返回原文的结果不标记为翻译成功。原生“显示原文/显示翻译”切换使用已有译文，不重新请求。

成功结果在进程内共用内存缓存，键包含推文 ID、原文和目标语言。重复请求合并，同一内容来回滑动不再重复翻译。进程退出清空缓存，长期使用的内存占用随成功文本增加。不承诺严格 0ms 渲染。

Google 通过 HTTPS translate.googleapis.com/translate_a/single（client=gtx、sl=auto、tl=zh-CN）翻译。补位时原文会发给 Google，不发送 X 登录令牌、Cookie 或账号信息。GTX 没有免限流承诺，可能返回 429 或不可用；Google 请求最多并发两条，每秒启动至多一条，429/503 遵守 Retry-After 并全局退避，其他错误有限重试。两通道不可用时保留原文。

## 日志与验证

保留屏幕“日志”按钮、实时日志和导出日志。新增原生状态、译文验证结果、包装器类型、注册结果和动态通知数量；不记录正文、完整请求 URL、账号令牌。XAD_DIAGNOSTICS=0 编译移除诊断 UI 和日志写入。

bash scripts/build-ios.sh 使用 Apple SDK 构建。GitHub Actions 用模拟原生包装器复现 representedStatus 指向原文的结构，验证译文提取、拒绝原文、Google 原生显示、动态更新通知、显示原文、双通道缓存/切换及 429 退避，再构建带日志及无日志版本，检查签名和 Mach-O。模拟测试与编译不代替手机实测。build-info.txt 记录提交、工具链和文件哈希。
