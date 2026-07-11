<div align="center">
  <img src="https://github.com/slinxlink/node/raw/main/web/src/asset/image/logo.webp" width="50" />
  <h1>SLINX ruleset</h1>
  <p>为 sing-box 核心提供的 .srs 格式规则集</p>

  [![License](https://img.shields.io/badge/license-MIT-blue.svg?longCache=true)](LICENSE)
</div>

> [!IMPORTANT]
> 本项目仅供个人使用。请勿将其用于非法目的，也请勿在生产环境中使用。

## 简介

本仓库为 sing-box 核心提供 .srs 格式规则集，基于 sing-box 官方的 geoip 和 geosite 仓库生成。
目前为不定期维护状态。

## 规则集分组说明

`site/` 目录下每个 `.srs` 文件都是按主题打包的域名规则集，来源于 sing-box 官方 geosite 仓库对应的 tag，具体包含的 tag 如下：

| 文件 | 包含 tag |
| --- | --- |
| `ai.srs` | anthropic apple-intelligence github github-copilot google-gemini openai perplexity |
| `media.srs` | apple-tvplus dazn disney hbo hulu iqiyi@!cn netflix primevideo spotify tiktok tvb youtube |
| `social.srs` | discord facebook instagram line telegram threads twitter whatsapp x |
| `game.srs` | ea epicgames nintendo playstation steam xbox |
| `apple.srs` | apple icloud icloudprivaterelay itunes |
| `google.srs` | google |
| `microsoft.srs` | bing microsoft onedrive |

`ip/` 目录下则是基于 IP 段匹配的 geoip 规则集（如 `cn.srs`），用于国内/国外 IP 归属判断。

## 社区

[![Telegram](https://img.shields.io/badge/Telegram-@SLINXlink-26A5E4?logo=telegram&logoColor=white)](https://t.me/slinxlink)

## 鸣谢

- [sing-geoip](https://github.com/SagerNet/sing-geoip) — geoip 规则源数据
- [sing-geosite](https://github.com/SagerNet/sing-geosite) — geosite 规则源数据

## License

[MIT](LICENSE)