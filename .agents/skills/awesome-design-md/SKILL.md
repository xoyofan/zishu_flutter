---
name: awesome-design-md
description: 74 套取自知名网站真实设计系统的 DESIGN.md（Vercel、Linear、Stripe、Apple、Airbnb、Binance、Figma、Notion、Supabase、Sentry、Raycast、Claude、xAI 等）。当用户要求"做成某某品牌的风格/质感"、"给我一份 DESIGN.md / 设计系统文档 / design tokens"、"配色、字体、间距、组件规范"、"让 UI 更像 XX 产品"，或要为项目建立/刷新视觉基线时使用。用法：按品牌读取 references/<brand>.md，把其中的 tokens 与规则作为唯一视觉真源来生成 UI。
---

# Awesome DESIGN.md

`DESIGN.md` 是 Google Stitch 提出的设计系统文档格式：一个纯 Markdown 文件，AI 编码 Agent 读它就能生成风格一致的 UI。它和 `AGENTS.md` 是同一层思路的两种文档：

| 文件 | 读者 | 定义什么 |
|---|---|---|
| `AGENTS.md` | 编码 Agent | 项目**怎么搭**（架构、约定、命令） |
| `DESIGN.md` | 设计/UI Agent | 项目**长什么样**（配色、字体、间距、组件、响应式） |

本 skill 内置 74 套逆向自真实网站的设计系统，集合内有**两种格式**，读法不同：

| 格式 | 套数 | 特征 | 读法 |
|---|---|---|---|
| **B** | 64 | 有 YAML frontmatter，`colors:` / `typography:` 等 tokens 是结构化定义 | 先读 YAML 取 tokens，再按需读正文 |
| **A** | 10 | 无 YAML；正文用 `## 1.` – `## 9.` 编号章节，值以 hex 散在段落里 | 先读 `## 2. Color Palette & Roles` 与 `## 3. Typography Rules` 自己提值 |

格式 A 的 10 套：`kraken`、`lamborghini`、`lovable`、`mastercard`、`runwayml`、`sanity`、`spotify`、`starbucks`、`tesla`、`theverge`。

两种都是完整设计规格，不是"风格关键词清单"；差别只在 token 有没有被 YAML 结构化。

## 何时使用

适用：

- 用户说"做一个像 Vercel / Linear / Stripe / Apple 那样的界面"。
- 需要为新页面/新项目定视觉基线，但没有 Figma 稿、没有现成设计规范。
- 需要具体的 design tokens（颜色 hex、字号阶梯、间距刻度、阴影、断点）。
- 要给现有项目补一份 `DESIGN.md`，让后续所有 UI 生成有统一依据。
- 评审 UI：拿 DESIGN.md 的 Do's/Don'ts 与 Responsive 章节当检查表。

不适用：

- 解析核心、爬虫、播放器内核等非视觉逻辑。
- 需要精确复刻某个**已有项目**的自家设计系统（应直接读该项目的 tokens 源文件，而不是套用外部品牌）。
- 需要位图级还原某张设计稿（本 skill 给的是设计语言，不是设计稿）。

## 使用流程

1. **选品牌**：从下方目录挑与目标气质最接近的 1 套。**一次只选一套**——混用 2 套以上品牌系统必然产生风格冲突。
2. **读文件**：`read` 对应 `references/<brand>.md`（绝对路径按本 skill 目录解析）。文件较长（500–1500 行），**先看开头有没有 YAML frontmatter**：
   - 有（格式 B，64 套）：先读 YAML 拿 tokens，再看 `## ` 章节标题决定深入哪节。
   - 没有（格式 A，10 套）：直接读 `## 2. Color Palette & Roles` 与 `## 3. Typography Rules` 提值，
     并在回答里**列出你提取的 hex/字号**（无结构化校验，必须自证出处）。
3. **落成项目文件**：
   - 新项目：把 DESIGN.md 内容拷到项目根 `DESIGN.md`，并按项目实际删改（去掉不适用的品牌独有元素）。
   - 已有项目：**不要**直接用外部品牌覆盖项目 tokens。而是提取其中的结构化部分（间距刻度、字号阶梯、无障碍对比、响应式收缩策略），映射到项目现有 token 文件，只补齐缺口。
4. **按 tokens 生成 UI**：所有色值/字号/间距/圆角/阴影只能引用 tokens，不得在组件里写裸值。生成后自检一遍 `Do's and Don'ts` 与 `Responsive Behavior`。

## 目录结构

```text
awesome-design-md/
├── SKILL.md              # 本文件：索引 + 使用规则
└── references/
    ├── vercel.md         # 每个文件 = 一套完整 DESIGN.md
    ├── linear.app.md     # 文件名即品牌名，对应下方目录里的 <brand>
    └── ...
```

## 可用设计系统（74 套）

| 品牌 | 风格要点 |
|---|---|
| `airbnb` | A warm, generous consumer marketplace anchored on a clean white canvas and Airbnb Rausch (#ff385c), the single brand vol |
| `airtable` | A sober, editorial workflow-software interface anchored on white canvas and dark-ink type, where brand voltage comes fro |
| `apple` | A photography-first interface that turns marketing into a museum gallery. |
| `binance` | A confident financial-platform interface anchored on a deep near-black canvas, where Binance's iconic yellow (#FCD535) c |
| `bmw` | BMW's corporate site — distinct from BMW M's motorsport-bombastic variant, this is a measured and settled corporate-auto |
| `bmw-m` | A motorsport-engineering interface anchored on a near-black canvas with white BMW Type Next Latin display headlines in c |
| `bugatti` | An austere luxury-automotive interface that uses near-pure black canvas, white uppercase letterspaced display, and full- |
| `cal` | A clean, calendar-software-first interface anchored on white canvas with black primary CTAs and custom Cal Sans display  |
| `claude` | A warm-canvas editorial interface for Anthropic's Claude product. |
| `clay` | A vibrant claymation-meets-data interface for Clay.com (GTM data-orchestration platform). |
| `clickhouse` | A high-performance database interface anchored on near-pure black canvas with electric yellow as the brand voltage. |
| `cohere` | Cohere's 2026 web system is a controlled enterprise AI interface built from stark white editorial space, deep green-blac |
| `coinbase` | An institutional-grade crypto exchange whose marketing surfaces read like a quietly-confident financial-services brand. |
| `composio` | A developer-tools brand for AI-agent tool integration whose marketing surfaces lean into a dark, technical aesthetic wit |
| `cursor` | An AI-first code editor whose marketing site reads like a quietly-confident developer-tools brand with a warm-cream edit |
| `dell-1996` | An inspired interpretation of Dell.com's 1996 design language — a catalog-era enterprise web design built around a liter |
| `elevenlabs` | A voice-AI brand whose marketing surfaces read like a quietly editorial print magazine. |
| `expo` | A React Native developer-platform whose marketing site reads like a quietly-confident infrastructure brand. |
| `ferrari` | A luxury-automotive brand whose marketing surfaces read as cinematic editorial. |
| `figma` | A confident black-and-white editorial frame interrupted by oversized, hand-cut pastel color blocks. |
| `framer` | A confident dark-canvas builder marketing site that treats the page like a working artboard — pure black surfaces, white |
| `hashicorp` | An enterprise-infrastructure marketing canvas built around a near-black ground (#000000) and a system of per-product acc |
| `hp` | An inspired interpretation of HP's design language — a white-paper enterprise-consumer system anchored by HP Electric Bl |
| `ibm` | An enterprise-marketing canvas faithful to Carbon Design System: white surfaces, charcoal type, IBM Blue (#0f62fe) as th |
| `intercom` | An editorial customer-service marketing canvas built around a soft cream-white ground, charcoal type set in Saans (Inter |
| `kraken` |  |
| `lamborghini` |  |
| `linear.app` | A near-black product-focused marketing canvas built around #010102 (the deepest dark surface of any tool in this collect |
| `lovable` |  |
| `mastercard` |  |
| `meta` | Meta's design system spans hardware commerce (Quest VR, Ray-Ban Meta AI glasses) and brand surfaces with a confident pro |
| `minimax` | MiniMax presents itself as a premium AI infrastructure brand through a striking duality — bold black-pill CTAs and stark |
| `mintlify` | Mintlify presents documentation infrastructure with a dual-mode aesthetic — atmospheric sky-gradient marketing heroes (c |
| `miro` | Miro presents itself as the AI-powered visual workspace through a confident, almost playful brand voice — anchored by it |
| `mistral.ai` | Mistral AI brands itself with a singular signature — atmospheric sunset gradients (mustard, orange, deep red) layered ov |
| `mongodb` | MongoDB carries a strong dual-mode visual identity — dark deep-teal hero bands with bright MongoDB green ({colors.brand- |
| `nike` | | |
| `nintendo-2001` | An analysis of Nintendo.com's 2001 design language — a brushed-periwinkle "console chrome" interface where every panel i |
| `notion` | Notion presents itself as the all-in-one workspace through a confident, illustration-rich brand voice — anchored by a de |
| `nvidia` | | |
| `ollama` | | |
| `opencode.ai` | | |
| `pinterest` | | |
| `playstation` | | |
| `posthog` | | |
| `raycast` | | |
| `renault` | | |
| `replicate` | | |
| `resend` | | |
| `revolut` | | |
| `runwayml` |  |
| `sanity` |  |
| `sentry` | An inspired interpretation of Sentri's design language — a developer-tools brand built on a deep purple-violet midnight  |
| `shopify` | An inspired interpretation of Shopifi's design language — a cinematic commerce platform that runs two parallel design tr |
| `slack` | An inspired interpretation of Slacc's design language — a workplace messaging brand built on a deep aubergine primary, w |
| `spacex` | An inspired interpretation of Spasex's design language — a mission-oriented aerospace brand built on pure black canvas,  |
| `spotify` |  |
| `starbucks` |  |
| `stripe` | An inspired interpretation of Stripi's design language — a financial-infrastructure brand built on a deep navy ink, an e |
| `supabase` | An inspired interpretation of Supabaze's design language — an open-source database platform built on a clean white-and-n |
| `superhuman` | An inspired interpretation of Superhumon's design language — a fast-email productivity brand split between an editorial  |
| `tesla` |  |
| `theverge` |  |
| `together.ai` | An inspired interpretation of Together AI's design language — an AI infrastructure platform whose surface alternates bet |
| `uber` | An inspired interpretation of Uber's design language — a transportation-and-delivery super-app brand whose web surface i |
| `vercel` | An inspired interpretation of Vercel's design language — a developer-platform brand whose surface is a stark black-and-i |
| `vodafone` | An inspired interpretation of Vodafone's design language — a telecom super-brand whose web surface alternates between ed |
| `voltagent` | An inspired interpretation of Voltagent's design language — a developer-focused AI agent engineering platform whose surf |
| `warp` | An inspired interpretation of Warp's design language — an agentic terminal-and-development-environment brand whose surfa |
| `webflow` | An inspired interpretation of Webflow's design language — a visual web development platform whose surface contrasts a de |
| `wired` | An inspired interpretation of Wired's design language — a flagship technology-magazine brand whose surface is a strict e |
| `wise` | An inspired interpretation of Wise's design language — a global money-transfer brand whose surface combines an unusually |
| `x.ai` | An inspired interpretation of xAI's design language — Elon Musk's frontier-AI company whose web surface is a strict near |
| `zapier` | An inspired interpretation of Zapier's design language — a workflow-automation platform whose surface combines warm-crea |

## DESIGN.md 的两种章节骨架

**格式 B（64 套，有 YAML frontmatter）** —— 先读 YAML 取 tokens，再按需跳正文：

| 正文章节 | 内容 |
|---|---|
| `## Overview` | 气质、密度、设计哲学 |
| `## Colors` | 语义色名 + hex + 功能角色 |
| `## Typography` | 字体族 + 完整字号阶梯 |
| `## Layout` | 间距刻度、栅格、留白哲学 |
| `## Elevation & Depth` | 阴影系统、层级关系 |
| `## Shapes` | 圆角与形态 |
| `## Components` | 按钮、卡片、输入框、导航的各状态 |
| `## Do's and Don'ts` | 设计护栏与反模式 |
| `## Responsive Behavior` | 断点、触控目标、收缩策略 |
| `## Iteration Guide` / `## Known Gaps` | 迭代建议与已知缺口 |

**格式 A（10 套，无 YAML）** —— 值都在段落里，需要自己提取：

1. `## 1. Visual Theme & Atmosphere` — 气质与设计哲学（含 Key Characteristics 要点列表）
2. `## 2. Color Palette & Roles` — hex 与功能角色（散在正文，逐条抄）
3. `## 3. Typography Rules` — 字体族与字号阶梯
4. `## 4. Component Stylings` — 组件与各状态
5. `## 5. Layout Principles` — 间距与栅格
6. `## 6. Depth & Elevation` — 阴影与层级
7. `## 7. Do's and Don'ts` — 护栏与反模式
8. `## 8. Responsive Behavior` — 断点与收缩
9. `## 9. Agent Prompt Guide` — 速查色板 + 可直接复用的提示词

## 硬约束

- **一次一套品牌**。跨品牌混用颜色/字体阶梯是最高频的错误。
- **字体名不等于字体可用**。DESIGN.md 里常写品牌私有字体（如 `Linear Display`、`Geist`）；落地前先确认项目里有没有该字体文件，没有就按其 fallback 顺序选系统字体，并在项目 DESIGN.md 里写明实际替换。
- **只取设计语言，不取商标资产**。禁止复制品牌 logo、商标字形、专有插图。
- **对比度优先于"像"**。品牌色用于大面积文本时先验证对比度，必要时改用该文件的 `on-*` 语义色。
- **不要把 DESIGN.md 当代码生成器**。它是规范来源；真实落地要经过项目自己的 token 层（如 Flutter 的 `AppColors`/`AppSpacing`/`AppTypography`）。
- 从外部仓库更新时，保留本目录结构（`SKILL.md` + `references/<brand>.md`），文件名用小写品牌名，避免路径大小写在 Windows 上出问题。

## 输出要求

使用本 skill 产出 UI 时，回答里至少包含：

1. 采用了哪一套 DESIGN.md，为什么选它；
2. 映射到项目 token 的对照（新增了哪些 token、复用了哪些）；
3. 与所选 DESIGN.md 的有意偏离及原因（字体缺失、无障碍、平台差异等）。
