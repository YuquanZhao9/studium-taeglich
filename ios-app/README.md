# 看课 iPhone App

一个很薄的外壳：打开 https://yuquanzhao9.github.io/studium-taeglich/player/ （播放器网页本身照常在 `player/` 里改，App 下次打开就是新版，不用重装）。

外壳只多做这几件事：

- 全屏时把整台 iPhone 转成横屏（开着「竖排方向锁定」也行），系统手势（从底边上滑切换 App）照常可用；退出全屏转回竖屏。手机没锁方向时，竖着拿横过来也会自动全屏。
- 没有 Safari 的「沿边一滑就返回」。
- 下拉刷新；静音键开着也有声音；alert / confirm / prompt 用系统弹窗。
- App-Bound Domains（`Kanke/Info.plist`）让网页的离线缓存 / service worker 在 App 里也能用。

网页和外壳通过 `window.webkit.messageHandlers.kanke.postMessage({fs: true|false})` 对话（`player/index.html` 里的 `app`）。

## 第一次安装（在 Mac 上，需要 Xcode）

1. Xcode → Settings → Accounts → 「+」用自己的 Apple ID 登录（免费账号就行）。
2. 打开 `Kanke.xcodeproj` → 左侧点 Kanke → Signing & Capabilities → Team 选自己的名字（Personal Team）。
   如果提示 Bundle Identifier 被占用，把 `com.yuquanzhao.kanke` 改成别的（比如结尾加数字）。
3. iPhone 用线连上 Mac、解锁、点「信任」。iPhone 上打开 设置 → 隐私与安全性 → 开发者模式（要重启）。
4. Xcode 顶部选中这台 iPhone，点 ▶ 运行。
5. 第一次打开会说「不受信任的开发者」：iPhone 设置 → 通用 → VPN 与设备管理 → 点自己的 Apple ID → 信任。

## 每 7 天

免费签名 7 天过期（过期后 App 打不开，但数据还在）。iPhone 连上 Mac，双击 `重新安装.command`，或者在 Xcode 里再点一次 ▶。不要先删掉 App，直接覆盖安装才能保留下载的课和进度。
