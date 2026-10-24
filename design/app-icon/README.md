# App icon

应用使用 `mssh/Resources/AppIcon.icon`，由用户提供的两份 Icon Composer 文件合并：

- 默认：浅色背景、黑色 `$`。
- Dark：深灰背景、白色 `$`。
- Mono：使用白色符号，由系统生成透明及着色外观。

`originals/light.icon` 和 `originals/dark.icon` 保留用户原稿。两份 SVG 原样复制；深色原稿的浅色背景在合并版本中调整为深灰渐变。各外观的折射和透明度设置沿用原稿。

构建使用 Xcode 26.6；新版原稿的 `features: ["specular-location"]` 会使其 `actool` 崩溃，合并版本移除此声明，并将 `specular: "outside"` 转为 `true`。升级 Xcode 27 后可恢复精确的外侧高光位置；两份原稿保留完整设置。

图标外观由主屏幕设置控制，与应用内的外观设置独立。XcodeGen 使用 `project.yml` 中的 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`；Xcode 26 优先使用同名 `.icon`，并为旧版系统生成兼容图像。

参考：[Apple — Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。
