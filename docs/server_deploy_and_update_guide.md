# 服务端部署与更新手册

> 这份手册**随仓库公开**（2026-10-07 起；`docs/` 里入库的就是它与 `cert_rotation_runbook.md`）。
> 三条写法约定：
>
> 1. **口令、密钥、令牌一律写成占位符**（`…`／`<…>`）—— 本手册里没有任何一个真值。
> 2. **服务器上的落地路径一律写 `$ROOT` 或 `<…>`**，照着部署时按自己的实际路径替换。
>    这里不写某一台机器上的绝对路径（历史版本写过，2026-10-07 摘掉：一台机器的目录名对别人没有价值，
>    对它的主人则是"代码目录 = 网站根"这种布局的自述）。**宝塔面板自身的固定目录**
>    （`/www/server/panel/vhost/nginx/…`、`/www/wwwlogs/…`）留着 —— 那是任何一台装了面板的机器都一样的
>    公开布局，不是某台机器的信息，去掉反而没人知道去哪儿改。
> 3. **真实域名保留**（与 README 一致）：`notice.fnthink.*` / `push.fnthink.*` 本来就是要给客户端填的公网服务地址。
>
> 最后更新：2026-10-07。

**术语**：`$ROOT` = 服务器上放 `server/` **内容**的那一级目录（你自己定，下文命令里按实际替换）。
代码位置解析契约时走的是 `lib/fnthink` 往上三级 ⇒ `$ROOT` 的**同级** `protocol/` 就是默认契约位置。

---

## 0. 现状快照（2026-09-29 复测；上一版 2026-09-28）

| 项 | 状态 |
| --- | --- |
| 更新服务 | **已上线**：`notice.fnthink.top`。⚠ 2026-10-06 起 App 侧**不再是编译期常量**：两档地址（`notice.fnthink.com` / `notice.fnthink.top`）住在 `lib/services/update_server_regions.dart`，应用内「更多 → 更新服务器」可选（T95） |
| 幻念推送公网面 | **代码就绪**：`/api/fnthink/{register,poll,ack,message,pair-arm,pair,pair-confirm}` + 三层限流 + 体积闸（#129/#130/#131）；**两个推送域名都已上线**（`.top` 见 8.9 第十一轮、`.com` 见 8.9 第十三轮，2026-09-29 外网实测：七条路由一律 403 `rejected_unsigned`、暴露七条一律 404、大 body 413+`{}`） |
| ⚠ 两域名在**两个不同的 CDN** 后面 | `.top` → Cloudflare；`.com` → 腾讯云 EdgeOne（`*.eo.dnse1.com`）。 ⇒ #140「真实客户端 IP」**不是一次修完两处**：两边的回源头不一样，要各配一次、各验一遍（验收命令见 8.9 第十三轮末尾） |
| 设备侧 fnthink 客户端 | **未做**（#126）。上线后公网面只有探针流量，没有真实推送 |
| 契约 | `protocol/fnthink-v1.json`（**不在 `server/` 里**，每次它变了必须重传） |
| 地理回读端点 | **两台都已部署并实测**（2026-10-07）：`GET /api/version/region` 回 `{country,source,edge}`。⚠ `.top`（Cloudflare）那台的 `.env` 还需要加一行 `FNTHINK_GEO_TRUST=cf`，那台的 `country` 才会出结论（没加就恒回 `country:null`，客户端自动退回只按实测时延挑一台 —— 不是故障）。实测记录与判定见 4.2/4.3 |
| 域名分工 | `notice.fnthink.top` = 更新/下载/管理后台；`push.fnthink.top`（海外）+ `push.fnthink.com`（大陆，已备案）= 幻念面 |

---

## 1. 两种部署形态

| 形态 | 上传物 | 结果 |
| --- | --- | --- |
| **A. 只装更新服务** | `server/` 内容而已 | `/api/fnthink/*` 一律 **503**（启动日志 `[fnthink] 协议入口没有起来`）。这是**正常**：那段没装，不是坏了 |
| **B. 更新服务 + 幻念面** | `server/` + `protocol/fnthink-v1.json` | 全部可用 |

⚠️ 形态 A 千万不要把契约复制进 `$ROOT`：服务器上那份才是被读的**真值**，仓库里改了不会生效（表现为"我改了契约没反应"）。

---

## 2. 首次部署（形态 A：只要更新服务）

```bash
# 1) 环境
node -v            # 期望 v24.x+（server/package.json 的 engines >=24，CI 同款）

# 2) 上传（在本仓库根执行；user@host 换成实际）
rsync -av --dry-run --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:$ROOT/
#    清单里不得出现 data/、.env、node_modules/，确认后去掉 --dry-run 再跑一次

# 3) 依赖
ssh user@host 'cd $ROOT && npm ci'

# 4) .env（首次）
cd $ROOT && cp .env.example .env
node -e "console.log(require('bcryptjs').hashSync('<管理员令牌>', 10))"    # → ADMIN_TOKEN_HASH
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"   # → ENCRYPTION_KEY（64 hex）
# .env 至少：
#   PORT=3456
#   NODE_ENV=production
#   ADMIN_TOKEN_HASH=…
#   ENCRYPTION_KEY=…
#   TRUST_PROXY=1            # 挂 Nginx 就设 1；Nginx+CDN 按跳数

# 5) 启动
pm2 start server.js --name update-server     # 或 systemd（见 README 方案四）
pm2 save && pm2 startup

# 6) 验证
curl -s localhost:3456/health                       # {"status":"ok","timestamp":"…"}
curl -s "localhost:3456/api/version/check?version=1.5.76&build=116&platform=android" | head -c 200
```

---

## 3. 加装幻念推送公网面（形态 B）

> 增量操作：1~3 步在线做完，不影响更新通道；第 4 步重启 1~2 秒。

### 3.1 传契约

```bash
# 默认位置：$ROOT 的同级 protocol/（代码按 lib/fnthink 往上三级找）
rsync -av ./protocol/fnthink-v1.json user@host:$ROOT/../protocol/
```

### 3.2 `.env` 加两行（推荐都写）

```ini
FNTHINK_CONTRACT=$ROOT/../protocol/fnthink-v1.json   # 显式声明（写错会在启动日志里当场暴露）
#RATE_LIMIT_FNTHINK_MAX=300                          # 公网面整面的每 IP 洪水闸（默认 300/分钟）
```

### 3.3 Nginx：给推送域名新增一个 server block

**不要**把推送域名塞进更新站点那个块里 —— 新增，且只放两个 location：

```nginx
server {
    listen 443 ssl;
    server_name push.fnthink.top push.fnthink.com;
    ssl_certificate     /etc/letsencrypt/live/push.fnthink.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/push.fnthink.top/privkey.pem;

    client_max_body_size 64k;      # 公网面协议闸也是 64 KiB；这里设小了会先被 Nginx 挡掉（回 HTML 413）

    location /api/fnthink/ {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    location /health { proxy_pass http://127.0.0.1:3456; }
    location /       { return 404; }        # 管理后台/官网只从 notice.* 进
}

# 80 → 443 的跳转块同样加上这两个域名
```

```bash
nginx -t && systemctl reload nginx      # reload，不是 restart
```

证书（一次性）：
```bash
certbot --nginx -d push.fnthink.top -d push.fnthink.com
```

### 3.4 访问日志脱敏（配对口令在路径里）

契约 `transport.secretPlacement = path_segment`：口令是 **URL 路径段** `/api/fnthink/p/<口令>`。
默认 combined 日志会把一枚一次性凭证原样写进 `access.log`。给这个站点单独一份 log_format：

```nginx
map $request_uri $safe_uri {
    default            $request_uri;
    ~^/api/fnthink/p/  "/api/fnthink/p/[redacted]";
}
log_format safe '$remote_addr - $remote_user [$time_local] "$request_method $safe_uri $server_protocol" '
                '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
access_log /var/log/nginx/push.access.log safe;
```

### 3.5 重启并核对横幅

```bash
pm2 restart update-server && pm2 logs update-server --lines 40
```
```text
协议面（fnthink-v1，公网可达）:
  POST /api/fnthink/register  - 按 IP 30/分钟 · 3000/天（身份未证明，只能按 IP）
  POST /api/fnthink/poll      - 按设备地址 14/分钟（数字从 presence 节奏推导，验签后计）
  （其余端点同理逐条打印）
  面的总量闸门（层 1，防单 IP 扇出）：300/分钟/每 IP
  请求体上限（公网面，取自契约 limits.requestBodyMaxBytes）：65536 字节
```
缺任何一行都别继续：`（协议面没有起来…）`= 契约没找到；`⚠ 请求体上限没挂上`= 同一原因。

---

## 4. 上线验收（5 条 curl 判定表）

```bash
curl -s  https://notice.fnthink.top/health                                    # {"status":"ok",…}
curl -s "https://notice.fnthink.top/api/version/check?version=1.5.76&build=116&platform=android"   # {"code":0,…}
curl -s -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://push.fnthink.top/api/admin/login          # 期望 404
curl -s -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' \
     -d "{\"pad\":\"$(head -c 70000 /dev/zero | tr '\0' 'x')\"}"                                   # 期望 413 + {}
```

| 结果 | 含义 | 处理 |
| --- | --- | --- |
| `/health` 非 200 | Node 没起 / 端口不对 | `pm2 logs` 看栈 |
| `version/check` 非 `{"code":0}` | **更新通道被弄坏了** | 立刻回滚（第 6 节） |
| 推送面 403 `rejected_unsigned` | ✅ 协议面活着 | —— |
| 推送面 **503** | 契约没找到 | 3.1/3.2 重做；看日志点名缺哪份文件 |
| 推送面 404 | Nginx 没写推送域名 | 3.3 的 `server_name` |
| 大 body 回 HTML 413 | `client_max_body_size` < 64k | 3.3 调大 |
| 推送面 429 | 触到了限流（探针连发时正常） | 等窗口过去；`Retry-After` 有秒数 |

### 4.1 中文探针的姿势（T85b，2026-10-01 固化；两次现场重踩才写下来的）

**坑有两只，方向不同：一只在发出去的那一侧，一只在读回来的那一侧。混淆它们会让人白花一轮。**

**① 发出去：`curl -d` 里内联中文，发出去的不是 UTF-8 字节。**
本机是 Git Bash（mingw64）+ 中文 Windows：命令行里的中文会被按 **GBK** 转成字节再交给 curl。
所以"内容看起来完全正确的一条 curl"到了服务端可能已经不是 UTF-8（8.110 诊断过一次，
2026-10-01 探测 `push.fnthink.com` 时原样重踩）。**规则：中文一律走文件，不走命令行。**

```bash
# 1) 先把载荷按 UTF-8 落盘（编辑器/`printf` 都行，别用 PowerShell 默认编码——它带 BOM）
# 2) 发之前自己数一下非 ASCII 字节：非 ASCII 应当只出现在你以为的那几个位置
LC_ALL=C tr -d '\000-\177' < payload.json | wc -c     # 0 = 全 ASCII；>0 = 有几个非 ASCII 字节
# 3) 发（用 --data-binary @，不是 -d "..."）
curl -s -X POST https://push.fnthink.top/api/fnthink/message \
     -H 'Content-Type: application/json' --data-binary @payload.json
```

**② 读回来：终端显示的不是真相，字节才是。**
本机控制台是 GBK：一段**完全合法**的 UTF-8 中文打上去会像乱码，而一段**坏掉的**字节打上去
也可能看着"像中文"。所以判断只看终端必然错。两条能判定的做法：

```bash
curl -s ... | iconv -f UTF-8 -t UTF-8 > /dev/null && echo "字节是合法 UTF-8" || echo "不是"
# 或者：管道进 python 数一遍（顺带能把 JSON 结构一起验掉）
curl -s ... | python -c "import sys,json;d=sys.stdin.buffer.read();print(len(json.loads(d.decode('utf-8'))))"
```

**③ 设备/客户端那一侧到底谁在解码（2026-10-01 用 `package:http` 实测，不是听说的）：**

| 响应的 `Content-Type` | `response.body` 实际按什么解 |
| --- | --- |
| `application/json`（无 charset） | **UTF-8**（所以线上此刻一直是好的） |
| `application/json; charset=utf-8` | UTF-8 |
| `text/plain`（无 charset） | **latin-1 ⇒ 中文变 mojibake** |
| 干脆没有 `Content-Type` | **latin-1 ⇒ 中文变 mojibake** |

⇒ 结论两条，都直接影响运维判断：
- **不要把响应头改成 `text/*`、也不要吃掉 `Content-Type`**。反代/CDN/WAF 这么改之后，
  设备侧不会报错，只会把中文**解成坏字符当真内容用出去**（落进收件表、上通知栏）。
  这就是"换设备后第一条推送是乱码"那一类报法最可能的成因之一。
  客户端自 T85(a)（提交 `6df9563`）起一律自己按 UTF-8 解字节（`utf8.decode(bodyBytes,
  allowMalformed: false)`），坏字节**抛错而不是静默替换** ⇒ 服务端/反代把类型改坏时，
  设备会判"这一发内容读不出"，不再显示坏字。
- 反过来，**服务端仍然应该带 `charset=utf-8`**：那是一层免费的纵深，别撤。

**④ 还有一条同族的坑（第 8.110 版就诊断过，这里一并钉住）：** 中文 Windows 上 `python -c` 的
`print` 会因为 GBK 控制台崩在编码上 —— 探针脚本一律**写报告文件再读**，不要往 stdout 打中文。
测试里同理：`http.Response('中文', …)` 在 `text/*` 下会**直接抛** `ArgumentException`，
要演"UTF-8 字节 + text/plain"必须用 `http.Response.bytes(...)`。

### 4.2 地理回读端点 `/api/version/region`（T96，部署后第一次必跑）

```bash
# 两台各问一次（**从外网问**，不要在服务器上 localhost —— 那没有 CDN 边缘，永远回 null）
curl -si https://notice.fnthink.top/api/version/region | grep -iE '^(cache-control|vary)|^\{'
curl -si https://notice.fnthink.com/api/version/region | grep -iE '^(cache-control|vary)|^\{'
```

期望（`.top` 那台的 `.env` 里已设 `FNTHINK_GEO_TRUST=cf`、且跑的是**含提交 `143d173`** 的那一份代码时）：

```json
{"code":0,"message":"success","data":{"country":"CN","source":"cf-ipcountry","edge":"unknown","sawCfHeaders":true}}
```

⚠ 两个读数别误判：
- **`sawCfHeaders` 不在响应里 ⇒ 跑的是旧代码**（`143d173` 之前那一份），这时 `.env` 里的 `FNTHINK_GEO_TRUST` 根本没人读，
  而 `.com` 那台仍然会被一发伪造的 `cf-ipcountry` 骗出结论 —— 判据就一条：对 `.com` 发
  `curl -sS -H 'cf-ipcountry: US' https://notice.fnthink.com/api/version/region`，**回 `US` 就是没部署到位**，
  新代码回的是 `"country":null` + `"geoHeaderUntrusted":true`。
- **`edge` 会是 `unknown`，这不是故障**：新实现不再从 `cf-*` 推断边缘（那条推断正是今天被证伪的）。
  想让 `.top` 报 `cloudflare` 就再设一行 `FNTHINK_EDGE=cloudflare`；`.com` 那台设 `FNTHINK_EDGE=edgeone`。

| 看到什么 | 含义 | 处理 |
| --- | --- | --- |
| 404 | 上传的不是这一版，或反代把 `/api/version/region` 挡了 | 先 `curl` 源站端口确认 Node 有这条路由，再看 Nginx location 是否只放行了 `/api/version/check` |
| `"source":"none","edge":"unknown"` 且这台是 `.top` | CF 的边缘没给 `cf-ipcountry` | 对同域名 `curl -si /health` 看响应头：有 `cf-ray` 却没 `cf-ipcountry` ⇒ 自定义头被中间某层剥掉了，顺着反代查；连 `cf-ray` 都没有 ⇒ 这台根本不在 CF 后面（域名/DNS 变了） |
| `"country":null` + `"source":"none"`（没有 `geoHeaderUntrusted`） | 这台**根本没收到**任何可信地理头：`.com`（EdgeOne）今天就是这个形状 —— 它不给自己地理结论的头，而 `cf-ipcountry` 在它身后是客户端可写的，服务端不猜 | 见下面的实测姿势（要的是它**自己的**头名，不是 `cf-ipcountry`） |
| `cache-control` 不是 `no-store` | 反代/CDN 改了缓存口径 ⇒ 第一个用户的国家码可能被发给后面的人 | 在该域名的 location 里显式 `add_header Cache-Control "no-store" always;`，重跑一遍 |
| `vary` 里没有 `cf-ipcountry` | 同上，共享缓存会按 URL 存一份 | 反代层补 `add_header Vary "cf-ipcountry";` |
| `"country":null` + `"geoHeaderUntrusted":true` | 边缘的地理头**到了**，但这台的部署没声明「这个头由边缘覆盖」⇒ 接口拒绝把它当结论（2026-10-07 实测：EdgeOne 会把客户端自带的 `cf-ipcountry` 原样透传进源站） | 在 `.top` 的 `.env` 加 `FNTHINK_GEO_TRUST=cf` 并重启；**`.com` 那台不要设**（它不覆盖，设了就是把选择权交给请求方） |
| `Cache-Control` 出现两条（一条 `no-store`、一条 `no-cache`） | 源站发的是 `no-store`；那条 `no-cache` 是边缘自己加的（`/health` 与 `/api/version/check` 上只有 `no-cache` —— 全局那份只管 `/api/admin*`，见 `server/lib/middleware.js`） | 只要 `no-store` 在场就不许存储，实测 `cf-cache-status:DYNAMIC` / `EO-Cache-Status:MISS`。要干净就在反代层去掉那条追加 |

**实测 EdgeOne 到底带了什么头**（一次就够，别常开；2026-10-07 已知它会透传 `cf-ipcountry`，所以这里要找的是**它自己的**那个头名）：`.env` 加 `FNTHINK_GEO_ECHO=1` → `pm2 restart update-server`
→ 从外网 `curl -s https://notice.fnthink.com/api/version/region` → 读 `headerNames` 里有没有形如
`x-geo-country` / `x-forwarded-*` 的候选（**只有名字，没有值**）。把要用的那个头名填进
`FNTHINK_GEO_HEADER=<头名>` + `FNTHINK_GEO_TRUST=header`（**两个都要**，只配头名接口仍回 null）、`FNTHINK_EDGE=edgeone`，重启，再 curl 一次确认 `source` 变成 `geo-header`，
**然后必须把 `FNTHINK_GEO_ECHO` 删掉/设回 0 再重启** —— 它是排查仪器，不是常态接口。

> ⚠ 这一条**不判"哪些算大陆"**：判据住在客户端（`lib/services/update_server_regions.dart` 那侧），
> 所以改判据不用重新部署服务端。`XX`（边缘判不出）与 `T1`（匿名代理）会照原样回，
> 客户端**不许**把它们当结论用。
> ⚠ 它也不用 `req.ip`：`TRUST_PROXY=0` 时源站看到的对端是 CDN 回源 IP（#140 同一件事），
> 而 `cf-ipcountry` 是边缘按**真实客户端 IP** 判好带过来的 ⇒ 这条接口不依赖反代跳数设得对不对。

### 4.3 2026-10-07 部署实测（本机对公网，两台各若干发）

这两条读数决定 T96 片2 的判据形状，**别凭印象重述**：

| 探什么 | `.top`（Cloudflare） | `.com`（腾讯 EdgeOne） |
|---|---|---|
| DNS（`nslookup … 223.5.5.5`） | CNAME → `singgcdn.singgnetworkcdn.com` → `172.64.229.10`（CF 段） | CNAME → `*.eo.dnse1.com` → `113.142.27.122` |
| `/api/version/region` 直问 | 200，`{country:"CN",source:"cf-ipcountry",edge:"cloudflare"}`；`CF-RAY …-NRT` | 200，`{country:null,source:"none",edge:"unknown"}` |
| **带 `-H 'cf-ipcountry: US'` 伪造** | 仍回 **CN** ⇒ CF **覆盖**入站那个头，伪造无效 | 回 **US** ⇒ EdgeOne **原样透传**，连 `edge` 都被带成 `cloudflare` |
| 缓存 | `cf-cache-status:DYNAMIC`，两条 `Cache-Control`（`no-store` + 边缘那条 `no-cache`） | `EO-Cache-Status:MISS`，一条合并的 `no-cache, no-store` |
| 回归 | `/api/version/check` 200（`1.5.76+116`，downloads 落 `cdn2.fnthink.top`）、`/health` 200 契约字段齐 | `/api/version/check` 200（同一版本，downloads 落 `cdn.fnthink.com`）、`/health` 200 |

⇒ 三条结论，都已经写进代码与用例：
1. **源站无法分辨地理头是谁写的** ⇒ 信任只能由部署声明（`FNTHINK_GEO_TRUST`），**没声明就不出结论**；
   `.top` 该设 `cf`，`.com` 那台**不该设**（它不覆盖，设了等于把"连哪一台"的选择权交给请求方）。
2. **`edge` 不再从 `cf-*` 推断**（那条推断就是今天被证伪的东西），只认 `FNTHINK_EDGE`；`cf-*` 在场降级为事实字段 `sawCfHeaders`。
3. 即便两台都不出结论，"自动"档仍然有可用的判据 —— 实测时延（片4 那一条路），这也是 fail-closed 之后界面上该说的话。

⚠ **还没测成的那一件**：`.com` 到底有没有自己的地理头。开 `FNTHINK_GEO_ECHO=1` 跑一发 curl 就问得出来
（只列头名不列值），问到之后 `FNTHINK_GEO_HEADER=<头名>` + `FNTHINK_GEO_TRUST=header` 一起设，再验一次 `source` 变成 `geo-header`，然后关掉 ECHO。
⚠ **也没测的一条**：`.com` 那台是否覆盖客户端自带的 `X-Forwarded-For`。这台接口不读 `req.ip` 所以与它无关，
但**在设 `TRUST_PROXY=1` 之前必须先问这一条** —— 若 EdgeOne 透传 XFF，那按 IP 的限流与封锁就能被伪造头绕过（#140 的另一个方向）。


**复验（同日 04:13 UTC，`143d173` 那份代码上线之后，本机对公网四发）**：

```bash
curl -sS https://notice.fnthink.top/api/version/region
curl -sS -H 'cf-ipcountry: US' https://notice.fnthink.top/api/version/region
curl -sS https://notice.fnthink.com/api/version/region
curl -sS -H 'cf-ipcountry: US' https://notice.fnthink.com/api/version/region
```

| 哪一台 | 回答 | 判读 |
|---|---|---|
| `.top` 明文 | `{"country":"CN","source":"cf-ipcountry","edge":"unknown","sawCfHeaders":true}` | ✅ `FNTHINK_GEO_TRUST=cf` 起作用了 |
| `.top` 伪造 | 同上（仍 **CN**） | ✅ 边缘覆盖入站头，伪造无效 |
| `.com` 明文 | `{"country":null,"source":"none","edge":"unknown"}` | ✅ 这台没有可信地理头 ⇒ 老实说"没结论" |
| `.com` 伪造 | `{"country":null,"source":"none","edge":"unknown","geoHeaderUntrusted":true,"sawCfHeaders":true}` | ✅✅ **洞堵上了**：头到了、值也成形状，但没声明信任 ⇒ 拒绝当结论 |

回归一并复跑：两台 `/api/version/check` 都 200（`1.5.76+116`；`.top` 的 downloads 落 `cdn2.fnthink.top`、`.com` 落 `cdn.fnthink.com`）、
`/health` 都 200 且契约字段齐（`contractVersion:1` / `protocolVersion:"fnthink-v1"` / 无 `contractError`）、
`POST /api/version/region` 两台都 404（只有 GET）。缓存口径没变：`no-store` 在 `.top` 上与边缘那条 `no-cache` 并列、
在 `.com` 上合并成 `no-cache, no-store`；`cf-cache-status:DYNAMIC` / `EO-Cache-Status:MISS`。

⚠ **两台现在都报 `edge:"unknown"`，这不是故障** —— 新实现不再从 `cf-*` 推断边缘。要让它报出名字各补一行：
`.top` → `FNTHINK_EDGE=cloudflare`、`.com` → `FNTHINK_EDGE=edgeone`（只用于展示与"哪一层在替你回答"那句话，客户端的判据不读它）。


---

## 5. 日常更新（每次改动上线）

```bash
# ① 备份（10 秒，出事救命）
ssh user@host 'cp -a $ROOT/data $ROOT/../backup/data-$(date +%F-%H%M)'

# ② 上传代码（+ 契约，若契约变了）
rsync -av --dry-run --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:$ROOT/
#    看到清单没问题再真跑；契约变了再：
rsync -av ./protocol/fnthink-v1.json user@host:$ROOT/../protocol/

# ③ 依赖（只有 package.json/package-lock.json 变了才需要）
ssh user@host 'cd $ROOT && npm ci'

# ④ 重启 + 读横幅（T96 之后横幅里应有 `GET  /api/version/region  - 地理回读` 一行；没有 ⇒ 上传的不是这一版）
ssh user@host 'pm2 restart update-server && pm2 logs update-server --lines 40'

# ⑤ 回归（每次都跑）
curl -s https://notice.fnthink.top/health
curl -s -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
```

**三条禁令**（README 里也写了，这里复述）：
1. 绝不 `rsync --delete` / SFTP 镜像模式 —— 会删掉 `data/totp.json`（管理员被锁在后台外）与幻念五张表；
2. 绝不覆盖 `data/`（含 `fnthink_devices.json` / `fnthink_pair_requests.json` / `fnthink_endpoints.json` / `fnthink_nonces.json` / `fnthink_messages.json`，那是设备公钥与授权关系）；
3. 绝不覆盖 `.env`（真实密钥）。

---

## 6. 回滚

```bash
# 代码与契约**同版本**，一起退
rsync -av <上一份 server/> user@host:$ROOT/
rsync -av <上一份 protocol/fnthink-v1.json> user@host:$ROOT/../protocol/
ssh user@host 'pm2 restart update-server && pm2 logs update-server --lines 20'
```
`data/` 从没被覆盖，不需要动。要回到某个时点：停进程 → `cp -a $ROOT/../backup/data-<时间>/. $ROOT/data/` → 起进程。

---

## 7. 排障速查

| 日志关键字 | 原因 | 处理 |
| --- | --- | --- |
| `[fnthink] 协议入口没有起来` | 契约缺失/非法/版本不认 | 看后面点名的文件与键；重传或修 `FNTHINK_CONTRACT` |
| `请求体上限没挂上` | 同上（体积闸也读契约） | 同上 |
| `[fnthink:ratelimit] 端点种类未登记` | 有人加了路由没进契约名单 | 把端点加进契约 `limits` 的三份名单之一 |
| `Unhandled error:` + 500 | 代码 bug | 完整栈在 `pm2 logs`；先回滚 |
| 全体设备 429 且 `TRUST_PROXY` 未设 | 反代后共用出口 | `.env` 设 `TRUST_PROXY=1` 并重启 |
| 管理后台登不进 | `data/totp.json` 丢 or 会话表坏 | 见 README「手动重置二步验证」 |

---

## 8. 宝塔面板部署（BT Panel）—— 详细版

> 宝塔 = Nginx + 可视化进程/文件/证书管理。下面按"面板点哪里 + 等价命令 + 坑"写。
> 面板版本会让菜单名有出入（8.x/9.x 大致是「网站 / 文件 / 终端 / 软件商店 / 计划任务 / 安全」），
> **点不出来就用等价命令**，两条路等价。

### 8.0 与现有部署的关系（先读这条）

`notice.fnthink.top` **已经在线**。若它现在跑在手工 Nginx 配置上，**不要在宝塔里"重新建"这个站点** ——
宝塔只管理 `/www/server/panel/vhost/nginx/*.conf`，手工配置通常在别的目录；两套并存会出现
`duplicate server_name` / 80 端口争用。两个安全做法：
- **只想加推送面** → 在宝塔里**只新建推送站点**（8.4），更新站点保持原样；
- **想让宝塔接管全部** → 先把现有站点 conf 的内容**原样**贴进宝塔站点的「配置文件」里再启用，
  改完 `nginx -t`，并**立刻回归验证** `notice.*` 的 `/api/version/check`。

### 8.1 装面板与依赖（只装必要的）

1. 面板安装命令从**官网当前页面**取（版本间会变，别抄旧文）；
2. 软件商店：确认 **Nginx** 已装；**PHP / MySQL / phpMyAdmin 一律不装**（本项目用不到）；
3. 软件商店搜 `Node` → 装 **Node.js 版本管理器**（或 PM2 管理器）→ 安装 **24 LTS**；
   等价：面板「终端」里按 NodeSource 官方说明装 Node 24，再 `npm i -g pm2`。

### 8.2 上传代码与契约

**面板方式（可重复、可回滚）**
```text
本地：把 server/ 打成 zip —— 排除 data/、.env、node_modules/
面板：文件 → 进入 $ROOT → 上传 → 解压覆盖
```
- 面板解压只覆盖同名文件、不删别的文件（因为没有 --delete 语义），但**包里绝不能带本地的 `data/` 与 `.env`**；
- 上传前在本地看一眼 zip 清单（`unzip -l`），确认没有这三项。

**终端方式（与原手册一致）**
```bash
rsync -av --exclude 'data/' --exclude '.env' --exclude 'node_modules/' ./server/ user@host:$ROOT/
rsync -av ./protocol/fnthink-v1.json user@host:$ROOT/../protocol/      # 契约默认位置
cd $ROOT && npm ci
```

### 8.3 更新站点（notice.fnthink.top）

1. 网站 → 添加站点：域名 `notice.fnthink.top`，**不勾** FTP / 数据库；
2. 反向代理 → 添加：目标 `http://127.0.0.1:3456`，发送域名 `$host`；
3. 站点「配置文件」里**核对/补齐**三行（宝塔模板有时只带前两行）：
   ```nginx
   proxy_set_header Host $host;
   proxy_set_header X-Real-IP $remote_addr;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   ```
4. 同文件加 `client_max_body_size 2m;`（管理面 ≥1 MB；公网面 64 KiB 由应用自己回 413）；
5. SSL → Let's Encrypt 申请（`notice.fnthink.top`，勾自动续期）→ **申请完回去复查第 3 步三行**。

### 8.4 推送站点（push.fnthink.top + push.fnthink.com）—— 反代细节

反代是这一节的全部内容，也是"两个域名靠配置分开"的落点。分四步：

**① 建站**：网站 → 添加站点，域名两行都填（宝塔支持一站多域名，`server_name` 会自动写成一行两名）；
根目录留默认（不放任何文件）；**不建** FTP / 数据库。

**② 加两条反向代理**（面板一次只能加一条）：

| 名称 | 代理目录 | 目标 URL | 发送域名 |
| --- | --- | --- | --- |
| `fnthink` | `/api/fnthink/` | `http://127.0.0.1:3456` | `$host` |
| `health` | `/health` | `http://127.0.0.1:3456` | `$host` |

⚠️ **目标 URL 不要带路径、不要以 `/` 结尾**。`proxy_pass` 尾部带 `/` 会把 location 前缀替换掉 ⇒
上游收到 `/poll` 而不是 `/api/fnthink/poll` ⇒ 整面 404，而服务器上直连上游 **403（正常）** ——
"上游好的、外面 404"就是这一条。宝塔输入框里只填 `http://127.0.0.1:3456`。

**③ 站点配置文件的最终形状**（把面板生成的拼起来，核对下面每一处）：

```nginx
# ── 顶部（server{} 之外、仍在 http{} 内，宝塔的站点 conf 是被 include 进 http 的）──
map $request_uri $safe_uri {
    default            $request_uri;
    ~^/api/fnthink/p/  "/api/fnthink/p/[redacted]";   # 配对口令在路径段，别写进日志
}
log_format safe '$remote_addr - $remote_user [$time_local] "$request_method $safe_uri $server_protocol" '
                '$status $body_bytes_sent "$http_referer" "$http_user_agent"';

server {
    listen 80;
    server_name push.fnthink.top push.fnthink.com;
    rewrite ^(.*)$ https://$host$request_uri permanent;   # 契约 httpsOnly=true，先跳 https
}
server {
    listen 443 ssl;
    server_name push.fnthink.top push.fnthink.com;
    ssl_certificate     /etc/letsencrypt/live/push.fnthink.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/push.fnthink.top/privkey.pem;

    client_max_body_size 64k;      # 与服务端协议闸一致；设小了先被 Nginx 挡掉、回 HTML 而不是协议形状

    location ^~ /api/fnthink/ {
        proxy_pass http://127.0.0.1:3456;                    # ⚠ 无尾斜杠（有尾斜杠 ⇒ 整面 404）
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;          # 服务端目前不读，但写对不吃亏
    }
    location ^~ /health {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    location / { return 404; }     # 其余一律挡掉：管理后台/官网只从 notice.* 进

    access_log /www/wwwlogs/push.fnthink.top.log safe;
}
```

**不需要配的**：WebSocket / `Upgrade` 头（`/poll` 是立即返回的短请求）、任何静态目录、PHP、
`proxy_read_timeout` 之类的调优。**反代是 HTTPS 的唯一出口** —— 服务端不判 scheme（`httpsOnly` 只是契约
声明，`server.js` 里没有任何 `req.secure` / `x-forwarded-proto` 判据）且监听 `0.0.0.0`，所以 3456 一旦对
公网开放，明文投递也能通；这正是 8.6 要"只放行 80/443"的原因。

**④ SSL**：在同一站点里给两个域名一起申请（Let's Encrypt 支持多域名 SAN；面板申请界面把两行都填）。
**申请完复查 ① 的那三行 `proxy_set_header`** —— 面板重写 443 段时可能重排配置。

**配对自检（三条，能把"哪一层答的 404/502"分开）**

```bash
# ① 直连上游（绕开 Nginx）：应 403
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:3456/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# ② 经 Nginx：也应 403
curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://push.fnthink.top/api/fnthink/poll \
     -H 'Content-Type: application/json' -d '{}'
# ③ 管理面不该从这里进：应 404
curl -sk -o /dev/null -w '%{http_code}\n' https://push.fnthink.top/admin.html
```

① 403 + ② 404 ⇒ 反代配错（先查尾斜杠）；② 502 ⇒ 上游没起 / 端口不对；② 403 但 ① 也 403 ⇒ 反代已通。

**推送域名两个都上了（2026-09-29 复测；本节这一栏原先写的是"只配了 `.top`"）**

> 现状（2026-09-29 外网实测）：`push.fnthink.top` 与 `push.fnthink.com` **都在服务**，且行为一致
> （七条路由一律 403 `rejected_unsigned`、暴露一律 404、大 body 413+`{}`）。差别在**前面那层 CDN**：
> `.top` 走 Cloudflare，`.com` 走腾讯云 EdgeOne（CNAME `*.eo.dnse1.com`，边缘响应带 `EO-LOG-UUID` / `EO-Cache-Status`）。

- `server_name` **只写你已经解析、并且证书覆盖了的那个域名**。把没配的域名写进去，在 DNS 还没解析时看不出问题，
  一旦解析过去就是"证书不匹配"（浏览器要手动点过、客户端会直接拒连）；
- 以后要加第二个域名：先加 DNS 记录 → 重新签一张覆盖两个域名的证书（SAN）→ 再把它加进 `server_name` → `reload`；
- **不会因为少一个域名而报错的东西**（核对过）：服务端**完全不读** `transport.endpoints`（不拨号）；
  包侧的 validate 只校验域名的**形状与归属**（`.fnthink.top` / `.fnthink.com`）与 `default` 取值，
  与"是否已部署"无关。

⚠️ **`.com` 是独立站点还是同一个 server 块？实测区分不了，要在面板确认。** 8.4 上面那份 `server_name push.fnthink.top push.fnthink.com;`
两块都写，所以"外网两个域名行为一致"既可能是**同一块**（自然一致），也可能是**另建了一个站点/另一份边缘配置**（碰巧配得像）。
这个区分不是洁癖 —— 它决定**后面每处"改一处"的指引要改几次**：

- 若是**同一块**：本节那三项（`location / { return 404; }`、`client_max_body_size 64k`、两条 `#PROXY` 段的
  `proxy_pass` 不带尾斜杠 + `Host $host`）改一次就两个域名都生效；
- 若是**两个站点**：每一次都要**做两遍**（宝塔的站点配置、代理段、证书各自独立），漏一个域名的表现是
  "那个域名上一切正常，只有新改的这条没生效"。

**✅ 原"还没爆炸的地雷"已解除（2026-09-29）—— 走的是当时列的第 1 个选择。** 契约里
`transport.endpoints.mainland = push.fnthink.com` 声明的那个域名**现在真的在服务**了，
所以 `suggestSwitchOnMainlandNetwork: true` 不再会把大陆用户切到一个不存在的域名上；
第 2 个选择（改契约成 `false`）**不需要做了**，契约不用动。#137 到此收口。

⚠ **解除之后新露出来的两条（#126 设备侧客户端实现时要读）**：
1. **两个端点分处两个 CDN** ⇒ "切域名"在客户端侧不是中性的：边缘不同、回源链路不同、`X-Forwarded-For` 的语义也不同
   （#140 未修前，两域名各自的"每 IP 桶"里装的是各自 CDN 的回源地址）。
   客户端**不许**把"切到 mainland 失败"当成"网络有问题"去重试到对面域名上——那会同时消耗两把桶。
2. **边缘证书 2026-11-22 到期**（`CN=fnthink.com`，SAN `*.fnthink.com, fnthink.com`，Let's Encrypt）。通配符只能走 DNS-01，
   所以续期路径**要么自动（acme.sh + DNS API），要么手动重签再传边缘** —— 这一条要在面板确认是哪一种；
   到期没续上的表现是**整面对外断连**（客户端直接拒连，不是某个接口报错）。

### 8.5 启动进程（Node 项目 / PM2）

- 面板：网站 → **Node 项目** → 添加：启动文件 `server.js`、端口 `3456`、**运行目录 = `$ROOT`**、用户 `www`；
- 或终端：`cd $ROOT && pm2 start server.js --name update-server && pm2 save && pm2 startup`；
- ⚠️ **运行目录错了 = `.env` 读不到 = 启动即退出**（日志里一句"密钥未配置"）。这是面板环境最常见的坑；
- 开机自启：Node 项目/PM2 管理器里勾选，或 `pm2 startup`。

### 8.6 安全（面板特有的三项）

1. **安全页不要放行 3456**。服务监听 `0.0.0.0`，放行了就等于绕过 Nginx 的 HTTPS 与限流
   （`curl http://<IP>:3456/admin.html` 直接进管理后台）。只放行 **80 / 443**；
2. 面板自身：改入口路径与端口、开二次验证、限制面板 IP（有固定 IP 的话）；
3. 若日后给 server.js 加 `HOST` 支持（让其只听 `127.0.0.1`），可以在面板里彻底关掉 3456 的监听面 ——
   这一条属于代码改动，做之前先提。

### 8.7 备份与恢复（data/ 是身份数据）

- **计划任务 → 备份目录**：`$ROOT/data` 每日打包到一个**代码目录之外**的备份目录（`<BACKUP_DIR>`，宝塔的「计划任务 → 备份目录」里选），保留 14 天；
- 面板的「网站备份」备份的是站点根目录：如果 `data/` 在站点目录里，备份会带上它（好事），
  但**恢复时必须只恢复代码**，把 `data/` 排除掉 —— 否则设备表与配对关系会回滚到旧版本；
- 手工兜底：`cp -a $ROOT/data <BACKUP_DIR>/data-$(date +%F-%H%M)`（出任何事前先跑这一条）。

### 8.8 验收（宝塔环境）

```bash
curl -s  https://notice.fnthink.top/health
curl -s "https://notice.fnthink.top/api/version/check?version=1.5.76&build=116&platform=android"   # 回归
curl -s -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'   # 403 才对
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://push.fnthink.top/api/admin/login              # 404 才对
curl -s -H 'Range: bytes=0-0' -o /dev/null -w '%{http_code}\n' https://push.fnthink.top/apks/         # 404（推送域名不服务静态）
```

> ⚠ **两个推送域名各跑一遍**（`.top` 与 `.com`）。2026-09-29 的实测是**两个都跑过、结果一致**（8.9 第十一轮 + 第十三轮），
> 而"一致"不等于"同源"：它们前面是**两个不同的 CDN**。凡是只在一个域名上生效的改动，先按 8.4 那条"是不是两个站点"去查。

### 8.9 上线核查（外部探测）—— 2026-09-28 起逐轮实测，最新到第十三轮（2026-09-29）

> 探测从**外网**做（本机 curl；`--ssl-no-revoke` 是本机 schannel 的吊销检查会失败，不是服务器问题）。

```bash
D=push.fnthink.top
curl -sS --ssl-no-revoke --max-time 15 -o /dev/null -w 'health=%{http_code}\n' https://$D/health
curl -sS --ssl-no-revoke --max-time 15 -w '\ncode=%{http_code}\n' -X POST https://$D/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
curl -sS --ssl-no-revoke --max-time 15 -o /dev/null -w 'admin=%{http_code}\n' https://$D/admin.html
curl -sS --ssl-no-revoke --max-time 15 -o /dev/null -w 'notice health=%{http_code}\n' https://notice.fnthink.top/health
curl -sS --ssl-no-revoke --max-time 15 "https://notice.fnthink.top/api/version/check?version=1.5.76&build=116&platform=android" | head -c 120
```

**实测结果（2026-09-28）**

| 项 | 结果 | 判定 |
| --- | --- | --- |
| DNS `push.fnthink.top` | 解析到 **Cloudflare**（104.21.67.244 / 172.67.183.45 / IPv6） | ✅ 已解析；⚠ 见下方"CF 真实 IP" |
| TLS | 握手通过（重定向只有一跳，说明 CF→源站不是 Flexible） | ✅ |
| `notice.fnthink.top` `/health` | **200** | ✅ 更新通道正常 |
| `notice.fnthink.top` `/api/version/check` | `{"code":0,…"latestVersion":"1.5.76","latestBuild":116}` | ✅ 回归通过 |
| `push.*` `/admin.html` | **404** | ✅ 管理面没从推送域名进 |
| `push.*` `POST /api/fnthink/poll` | **404 + Express 的 `Cannot POST /poll`** | ❌ **反代前缀被削**（见下） |
| `push.*` `POST /api/fnthink/` | 404 + `Cannot POST /` | ❌ 同一原因 |
| `push.*` `GET /api/fnthink/poll` | 404 + `Cannot GET /poll` | ❌ 同一原因 |
| `push.*` `/health` | **301 → `/health/`**，跟随后 200 | ⚠ `location /` 兜底未生效（有别的规则在补尾斜杠） |
| 响应头 `Set-Cookie: server_session_…` | 服务端**不设任何 cookie**（只用 `x-session-id` 响应头） | ⚠ 来源未知（CF 或源站其它组件），待确认 |

**❌ 必须修：`proxy_pass` 尾斜杠把 `/api/fnthink/` 前缀吃掉了**

三条实证一致 —— 上游 Express 收到的路径是 `/poll`、`/`，而不是 `/api/fnthink/poll`、`/api/fnthink/`。
修法（二选一，改完 `nginx -t` + reload）：
```nginx
proxy_pass http://127.0.0.1:3456;                 # ① 去掉尾斜杠（推荐）
proxy_pass http://127.0.0.1:3456/api/fnthink/;    # ② 或者把前缀补进 proxy_pass（两者等价）
```
改完立刻验：`curl -sS -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'`
→ 期望 **403 + `{"receipt":"rejected_unsigned"}`**（现在是 404 + Express 错误页）。

**⚠ 顺手要落实的两件**

1. **`/health` 的 301**：说明 push 站点不是"只放两个反代 location、其余 404"的形状。按 8.4 第③步把
   `location / { return 404; }` 落实（现在显然有别的规则在补尾斜杠，管理面 404 是运气好而不是配置保证）。
2. **Cloudflare 后面的真实 IP**：CF 回源时源站看到的对端是 CF。要让服务端的限流/封锁按**真实客户端 IP** 计，
   在源站站点配置里做（二选一）：
   ```nginx
   # ① 用 CF 的头覆盖 XFF（最简单，且与 TRUST_PROXY=1 配套）
   proxy_set_header X-Forwarded-For $http_cf_connecting_ip;
   # ② 或在 http 段做 real_ip（需要维护 CF 的 IP 段列表）
   set_real_ip_from 173.245.48.0/20;   # …CF 全部段
   real_ip_header CF-Connecting-IP;
   proxy_set_header X-Forwarded-For $remote_addr;
   ```
   不做这条的后果：所有设备共享 CF 的 IP ⇒ 又一份"全员 429"的配方（本仓已经因为这个形状红过一次）。
   ⚠ `TRUST_PROXY` 仍按**源站自己的**跳数算（CF 已被上面处理掉 ⇒ 仍是 `1`）。

**第二轮实测（2026-09-28 晚，维护者改过设置之后）**

面板里现在的两条（维护者截图）：`fnthink → 代理目录 /api/fnthink → 目标URL http://127.0.0.1:3456`、
`health → /health → 同一目标`；两条"运行中"、缓存关闭。**但外网复测结果变了、没好**：

| 探测 | 第一轮 | 第二轮 |
| --- | --- | --- |
| `POST /api/fnthink/poll` | 404 `Cannot POST /poll` | 404 **`Cannot POST //poll`** |
| `POST /api/fnthink/` | 404 `Cannot POST /` | 404 **`Cannot POST //`** |
| `/health` | 301 → `/health/` 200 | 同（301 → `/health/` → 200） |
| `/admin.html` | 404 | 404 |
| `notice.*` 回归 | 200 / code 0 | 200 / code 0 |

⇒ 症状从"前缀被吃掉"变成"**多出一个斜杠**"，说明 `proxy_pass` 里**确实带了 URI**（一个 `/`），
而 location 匹配到的是不带尾斜杠的 `/api/fnthink` ⇒ 替换后得到 `//poll`。
⚠ **面板显示的目标 URL 不等于写进配置文件的值**（宝塔会给它补 `/`）—— 以【配置文件】里的
`proxy_pass` 行为准。

**成对关系表（照这个改，二选一即可）**

| 代理目录 | 目标 URL / `proxy_pass` | 上游收到（请求 `/api/fnthink/poll`） | |
| --- | --- | --- | --- |
| `/api/fnthink/` | `http://127.0.0.1:3456`（无 URI） | `/api/fnthink/poll` | ✅ 推荐 |
| `/api/fnthink/` | `http://127.0.0.1:3456/api/fnthink/` | `/api/fnthink/poll` | ✅ |
| `/api/fnthink/` | `http://127.0.0.1:3456/` | `/poll` | ❌ |
| `/api/fnthink` | `http://127.0.0.1:3456/` | `//poll` | ❌ ← 现在就是这个 |
| `/api/fnthink` | `http://127.0.0.1:3456/api/fnthink/` | `/api/fnthink//poll` | ❌ |

最稳：**代理目录写成 `/api/fnthink/`（带尾斜杠）+ 目标 URL 只写到端口**；保存后点【配置文件】确认那一行是
`proxy_pass http://127.0.0.1:3456;`（结尾直接是分号，没有任何路径）。

**验收（改完立刻跑）**

```bash
curl -sS --ssl-no-revoke -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
# 期望 403 + {"receipt":"rejected_unsigned"}；若还是 404，看 body 里 Express 报的路径对不对
```

**第三轮实测（维护者把代理目录改成 `/api/fnthink/` 之后）**

| 探测 | 结果 |
| --- | --- |
| `POST /api/fnthink/poll` | 404 **`Cannot POST /poll`**（症状从 `//poll` 又回到 `/poll`） |
| `POST /api/fnthink/register` | 404 `Cannot POST /register` |
| `POST /api/fnthink/` | 404 `Cannot POST /` |
| `/health` | 301 → `/health/` → 200（未变） |
| `/admin.html` | 404 ✓ |
| `notice.* /health` | 200 ✓（回归） |
| TLS | `ssl_verify_result=0` ✓ |

⇒ **结论钉死**：症状随"代理目录有没有尾斜杠"在 `/poll` 与 `//poll` 之间跳，但**根都是 `proxy_pass` 里的那个
URI（`/`）**；**面板的"目标 URL"字段改不掉它**（宝塔保存时会补回斜杠）。必须落到配置文件。

**第四轮：配置文件已确认（维护者贴出宝塔生成的块）**

```nginx
#PROXY-START/api/fnthink/
location ^~ /api/fnthink/
{
    proxy_pass http://127.0.0.1:3456/;                  # ← 元凶：结尾那个 `/`
    proxy_set_header Host 127.0.0.1;                    # ← 第二处：宝塔默认把发送域名写成 127.0.0.1
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header REMOTE-HOST $remote_addr;
    proxy_set_header Upgrade $http_upgrade;              # 本项目不需要 WebSocket，留着无害
    proxy_set_header Connection $connection_upgrade;
    proxy_http_version 1.1;
    add_header X-Cache $upstream_cache_status;           # 以下几行是面板的缓存/静态样板，对 POST API 无影响
    set $static_filen8mU3yye 0;
    if ( $uri ~* "\.(gif|png|jpg|css|js|woff|woff2)$" ) { set $static_filen8mU3yye 1; expires 1m; }
    if ( $static_filen8mU3yye = 0 ) { add_header Cache-Control no-cache; }
}
#PROXY-END/
```

⇒ 推断被证实：`proxy_pass` 的 URI 是 `/`，所以 `/api/fnthink/poll` 里的 `/api/fnthink/` 被替换成 `/`，
上游收到 `/poll`（这也解释了为什么"面板里怎么改都不对"—— 面板保存时会把自己那套模板重新写回这个块）。

**最小修法（只改两行）**

```diff
-    proxy_pass http://127.0.0.1:3456/;
+    proxy_pass http://127.0.0.1:3456;
-    proxy_set_header Host 127.0.0.1;
+    proxy_set_header Host $host;
```
`health` 那条（`#PROXY-START/health/`）大概率同样带 `:3456/;` 与 `Host 127.0.0.1;`，一并改。
保存 → `nginx -t && systemctl reload nginx` → 立刻跑下面两条验收。

⚠ **这段在 `#PROXY-START` / `#PROXY-END` 之间，属于面板管辖**：手改之后，只要以后在面板里再编辑/重建这条
反向代理，模板会把斜杠与 `Host 127.0.0.1` 一起写回。所以二选一：
- 接受"动过面板就复测一次"；或
- 采用**修法 A**（删掉面板条目、在 PROXY 块之外手写 location），一劳永逸。

**验收（改完立刻跑）**

```bash
curl -sS --ssl-no-revoke -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
# 期望 403 + {"receipt":"rejected_unsigned"}
curl -sS --ssl-no-revoke -o /dev/null -w '%{http_code}\n' -X POST https://push.fnthink.top/api/admin/login
# 期望 404
```

**修法 A（推荐：绕开面板）**——删掉面板里那两条反向代理，在 push 站点【配置文件】的 `server{}` 内手写：

```nginx
    # ── 幻念推送公网面（手写，避免面板给 proxy_pass 补 URI）──
    location ^~ /api/fnthink/ {
        proxy_pass http://127.0.0.1:3456;        # ⚠ 分号前没有任何路径：原样透传 /api/fnthink/…
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;   # 走 CF 时见下方"真实 IP"
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location ^~ /health {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    location / { return 404; }                   # 其余一律挡掉
    client_max_body_size 64k;
```
改完 `nginx -t && systemctl reload nginx`。

**修法 B（保留面板条目）**——在【配置文件】里把那行的结尾斜杠删掉：
`proxy_pass http://127.0.0.1:3456/;` → `proxy_pass http://127.0.0.1:3456;`，保存并 reload。
⚠ 以后在面板里再编辑这条反代时它**可能被补回**，所以每次动过面板都要复测一次本条 curl。

**验收（改完立刻跑，两条都要）**

```bash
curl -sS --ssl-no-revoke -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
# 期望 403 + {"receipt":"rejected_unsigned"}
curl -sS --ssl-no-revoke -o /dev/null -w '%{http_code}\n' -X POST https://push.fnthink.top/api/admin/login
# 期望 404（管理面不从这里进）
```

**第五轮实测（2026-09-28 夜，维护者按上面改完两行之后）—— 反代这关过了**

| 探测 | 结果 | 判定 |
| --- | --- | --- |
| `POST /api/fnthink/poll` | **503 + `{"error":"fnthink_protocol_unavailable"}`** | ✅ **反代已通**（应答来自上游应用的降级分支，不再是 Express 的 404 页）；❌ 缺契约文件 |
| `POST /api/fnthink/register` / `/api/fnthink/` | 同 503、同 body | 同上（降级挂在 `/api/fnthink` 前缀上，对任意子路径一致） |
| `/health` | 200（仍带 1 跳 301→`/health/`） | ⚠ health 那条反代没改（或站点里另有补斜杠规则） |
| `/admin.html` | 404 | ✅ |
| 大 body 70 KB | 503（契约没了 ⇒ 体积闸也没挂上，请求先落到降级分支） | 逻辑自洽，契约到位后再测 413 |
| `notice.* /health` | 200 | ✅ 回归 |

⇒ **下一步只剩"把契约传上去"**：`503 {"error":"fnthink_protocol_unavailable"}` 是 `lib/app.js` 里那段
"契约不可用 ⇒ 只降级这一段"的**专属响应体**（设计行为，管理面与更新通道不受影响）。做法二选一：
```bash
# ① 默认位置：代码目录的上一级 protocol/
rsync -av ./protocol/fnthink-v1.json user@host:$ROOT/../protocol/
# ② 或放任意位置 + .env 里显式指定
#   FNTHINK_CONTRACT=/绝对路径/fnthink-v1.json
pm2 restart update-server && pm2 logs update-server --lines 40   # 横幅应列出 7 个端点 + 请求体上限 65536
```
改完再跑验收：`poll` 应回 **403 + `{"receipt":"rejected_unsigned"}`**。

**仍欠**：`/health` 那条反代的两行（同 8.4 的修法）、`location / { return 404; }` 兜底、CF 后面的真实 IP、
以及那个来源不明的 `Set-Cookie: server_session_…`。

**第六轮（维护者贴出 health 的反代块）—— `/health` 那个 301 定位到了**

他贴的块：`location ^~ /health/`（**带尾斜杠**）+ `proxy_pass http://127.0.0.1:3456;` ✅ + `Host $host;` ✅。
判定实验：

| 请求 | 结果 | 说明 |
| --- | --- | --- |
| `/zzz-not-exist-42` | **404** | 不存在"无条件补斜杠"规则 |
| `/health` | **301 → `/health/`**，跟随后 200 | 只有它跳 ⇒ Nginx 的**目录补斜杠**行为（站点根下存在同名目录），而不是 rewrite |
| `/api/fnthink/poll` | 仍 **503** `fnthink_protocol_unavailable` | 反代已通；**契约还没传**（唯一阻塞项） |

⇒ 根因：`^~ /health/` **不匹配裸 `/health`** ⇒ 请求落到站点根的静态逻辑 ⇒ 因为是目录被 301 补斜杠 ⇒
第二次请求 `/health/` 才命中反代。而面板里他填的是 `/health` —— **宝塔又把"代理目录"规范化成了带尾斜杠**（又一次面板值≠生成物）。

**修法**：把那一行改成不带尾斜杠
```diff
- location ^~ /health/
+ location ^~ /health
  { proxy_pass http://127.0.0.1:3456; … }
```
改完 `/health` 会直接命中反代返回 200（不再有 301）。

**还欠的一步（阻塞协议面）**：把 `protocol/fnthink-v1.json` 传上去（见第五轮那两条命令），否则
`/api/fnthink/*` 一直是 503。

**那个来源不明的 cookie 怎么判定**（在服务器上跑，直连上游绕开 Nginx 与 CF）：
```bash
curl -sSI http://127.0.0.1:3456/health | grep -i set-cookie
# 有 ⇒ 我们服务端设的（不可能，代码里没有 res.cookie/setHeader('Set-Cookie')）⇒ 那就有别的东西在跑
# 无 ⇒ 是源站 Nginx（宝塔某模块）或 Cloudflare 加的
```

**第七轮：发现静态暴露（2026-09-28 夜，维护者贴出代码目录的文件清单与 `.env`）—— 🔴 必须立刻堵**

`push.fnthink.top` 的"网站目录"指向**代码目录**（本文后面一律记作 `$ROOT`），而站点根 `location /` 是宝塔的
静态直出 ⇒ 以下路径**全部 200、公网可直接下载**（`notice.fnthink.top` 上同样路径全是 404，说明主站没这问题）：

| 路径 | 状态 | 影响 |
| --- | --- | --- |
| `/server.js`、`/lib/store.js`、`/lib/routes/auth.js`、`/lib/fnthink/routes.js` | 200 | 全量源码 |
| **`/data/totp.json`** | 200 | TOTP secret 密文 + 恢复码 bcrypt 哈希 |
| **`/data/sessions.json`** | 200 | **活跃会话表**（`x-session-id` 凭据） |
| `/data/blocked_ips.json`、`/data/failed_attempts.json`、`/data/rate_limit.json` | 200 | 运行状态 |
| `/index.html`、`/public/admin.html` | 200 | 站点页与管理后台页面（需登录） |
| `/protocol/fnthink-v1.json`、`/data/version.json` | 200 | 本就是公开信息，无害 |
| `.env`、`.user.ini`、`.htaccess` | 403 | 宝塔默认挡点文件 ✅ |
| `data/fnthink_*.json` | 404 | 还没生成（协议面从未起来） |

**立即处置（按顺序）**

1. **堵住**：push 站点【配置文件】里把 `location /` 整段换成 `location / { return 404; }`（`^~ /api/fnthink/`
   与 `^~ /health` 两条反代不受影响），保存 + `nginx -t` + reload。修法 A（手写 location）同样有效。
2. **确认没被利用过**：
   ```bash
   grep -E "server\.js|totp\.json|sessions\.json|lib/" /www/wwwlogs/push.fnthink.top.log | head -20
   ```
   若只有这两轮探测的访问（客户端 IP 是你自己的/我探测用的），风险低；若有陌生 IP，按已泄露处理。
3. **按已泄露处理（建议都做）**：换 `ADMIN_TOKEN_HASH`（新令牌）+ 重绑 2FA（恢复码哈希也泄露了）+
   重启进程让会话失效（会话是持久化的，重启**不会**自动清 `sessions.json` ⇒ 用后台的会话管理/或临时把
   `data/sessions.json` 清空再重启）。
4. **`.env` 里那行路径写错了**（同一轮发现）：
   ```ini
   FNTHINK_CONTRACT=/protocol/fnthink-v1.json      # ✗ 以 / 开头 ⇒ 绝对路径 ⇒ 指向文件系统根的 /protocol/
   ```
   实际文件在 `$ROOT/protocol/fnthink-v1.json` ⇒ 契约读不到 ⇒ `/api/fnthink/*` 一直 503
   （这正是第五/六轮那个 `fnthink_protocol_unavailable` 的原因）。改成：
   ```ini
   FNTHINK_CONTRACT=$ROOT/protocol/fnthink-v1.json   # ✓ 要的是**实际绝对路径**（把 $ROOT 展开）
   ```
   或者把 `protocol/` 移到**代码目录的同级**（即 `$ROOT` 的上一级里）并删掉这一行走默认规则。

> ⚠️ **教训（写进公开 README 的那条）**：公网面站点的 `location / { return 404; }` 是**必须**而非加固 ——
> 站点目录 = 代码目录时，不写它等于把源码与 `data/` 一起挂到公网。

**第八轮：push 站点 server 块全文（维护者贴出）—— 要改的三处**

读出来的关键事实：`root` 直接指到**代码目录**（本文记作 `$ROOT`）、**没有 `location /` 段**（于是隐式静态直出
⇒ 暴露）、`error_page 404 /404.html;` 启用、`include enable-php-84.conf;`（PHP 8.4 解析，本服务用不到）、
反代从 `include /www/server/panel/vhost/nginx/proxy/push.fnthink.top/*.conf;` 引入（那两条 `^~` 反代在
那里）、宝塔自带一段"敏感文件"正则（挡 `.env*`/`README.md`/`package(-lock)?.json`/`.user.ini` 等 —— 与实测
`package.json` 404、`.env` 403 完全吻合）**但没挡 `server.js`/`lib/**`/`data/**`** ⇒ 那批 200。

**要改的三处（按重要性）**

1. 【必须】在 `#PHP-INFO-END` 之后加一行（不要放进任何 if 块）：
   ```nginx
   location / { return 404; }      # 只服务两条 ^~ 反代（它们不受影响）；其余一律 404
   ```
2. 【配套，防循环】把 `error_page 404 /404.html;`（ERROR-PAGE 段）**注释掉** —— 否则 `location /` 的 404 会
   内部跳到 `/404.html`、再落回 `location /` 又 404，Nginx 判定内部重定向循环后返回 **500**。
3. 【双保险，推荐】把该站点的**网站目录**改成空目录（别指向代码目录）；这样即使哪次面板操作把
   `location /` 段弄丢，静态直出也拿不到源码。

【可选】注释 `include enable-php-84.conf;` —— 这个站点是 Node 应用，不需要 PHP 解析（少一类攻击面）。

生效与验收：
```bash
nginx -t && systemctl reload nginx
for P in server.js data/totp.json data/sessions.json lib/store.js; do
  printf '%-22s %s\n' "$P" "$(curl -s -o /dev/null -w '%{http_code}' https://push.fnthink.top/$P)"
done     # 四条都必须是 404
curl -s -o /dev/null -w 'poll=%{http_code}\n' -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
# 403 = 全通（需先按 8.9 第七轮改 .env 的 FNTHINK_CONTRACT 并重启）；503 = 反代好了但契约还没生效
```

**第九轮：两个域名的静态根不是同一个（回答"会不会连累 notice"）**

实测对比（同一批路径打两个域名）：

| 路径 | notice.fnthink.top | push.fnthink.top |
| --- | --- | --- |
| `/index.html` | 200 | 200 |
| `/admin.html` | **200** | 404 |
| `/public/index.html`、`/public/admin.html` | **200 / 200** | —— |
| `/server.js`、`/data/**` | **404** | **200（暴露）** |
| `/apks/` | 404 | —— |

⇒ 两个 server 块**各有各的 root**：notice 的静态根是 `.../notice/public`（`/public/...` 还能命中，说明照
README 方案二配了 `location /public/ { alias …; }`），push 的静态根是**代码目录** `.../notice`。
**Nginx 的 `location` 作用域只在自己的 server 块内** ⇒ 在 push 块里加 `location / { return 404; }` **对
notice 零影响**；反过来 `include enable-php-84.conf;` 这类是"include 进各自块"，注释它也只影响本块。
⚠ 唯一要小心的动作是**"改网站目录"**：那只改 push 那一栏（改成新空目录），**绝不要动 notice 那一栏**
（它的 root 就是公开站点的内容）。

**如果根路径想有点东西**（维护者提的"给 fnthink push 做个介绍页"），不必放开静态目录：
```nginx
location = / { return 302 https://notice.fnthink.top/; }     # 推荐：想了解的人送去官网，零静态文件
# 或 location = / { default_type text/plain; return 200 "fnthink push endpoint\n"; }
location / { return 404; }                                    # 其余仍然全 404
```
`location = /` 是精确匹配、优先级最高（`location /` 抢不走），两条 `^~` 反代也不受影响。真要静态介绍页：
把该站点网站目录指向**新空目录** + `location = /index.html { root <新目录>; }`（注意 `location = /` 里的
`index index.html` 会内部跳到 `/index.html`，必须显式放行）。

**验收（改完连 notice 一起验）**
```bash
for P in server.js data/totp.json; do printf 'push %-16s %s\n' "$P" "$(curl -s -o /dev/null -w '%{http_code}' https://push.fnthink.top/$P)"; done   # 都要 404
curl -s -o /dev/null -w 'push poll=%{http_code}\n' -X POST https://push.fnthink.top/api/fnthink/poll -H 'Content-Type: application/json' -d '{}'
curl -s -o /dev/null -w 'notice health=%{http_code}\n' https://notice.fnthink.top/health                      # 仍须 200
curl -s "https://notice.fnthink.top/api/version/check?version=1.5.76&build=116&platform=android" | head -c 40 # 仍须 code 0
```

**第十轮：堵暴露后实测（2026-09-28 深夜）—— 暴露已堵住，且 `error_page` 那条推断被实测更正**

维护者按前面改完（`location = / { return 302 https://notice.fnthink.top/; }` + `location / { return 404; }`），外网实测：

| 探测 | 结果 | 判定 |
| --- | --- | --- |
| `/server.js`、`/lib/store.js`、`/data/totp.json`、`/data/sessions.json`、`/index.html` | **全 404** | ✅ **暴露已堵**（此前这批是 200） |
| `/` | **302 → notice.fnthink.top** | ✅ 根路径跳主站生效 |
| `/health` | **200、hops=0** | ✅ 顺带修好：不再有那次 301（health 的反代 location 已是不带尾斜杠的形状） |
| `POST /api/fnthink/poll` | 503 `fnthink_protocol_unavailable` | ❌ 只剩契约没生效（`.env` 的 `FNTHINK_CONTRACT` 待改） |

⚠ **一处自我更正**：第七/八轮我写的"`return 404` + `error_page 404 /404.html;` 会内部重定向循环、返回 500"
**未被实测支持** —— 保留 `error_page 404` 时这些路径依然干净地返回 404（Nginx 只把这一次响应内部改成去取
`/404.html`，不再对这一跳的响应套用 error_page）。所以那条的准确说法是：
- 不必为了"防 500"去注释它；但**仍建议注释**（省一次无意义内部跳转；且 `/404.html` 一旦真存在，会把站点里
  那个页面端出去）；
- 若谁真的看到 500 + `rewrite or internal redirection cycle`，再注释 `error_page 404` 即可。
（README 中英已按实测更正，不再声称必然 500。）

**第十一轮：部署侧全通（2026-09-28 深夜，最终验收）**

维护者改完（`location = /` 302 + `location /` 404 + 注释 `error_page 404` + 注释 PHP include + `.env` 的
`FNTHINK_CONTRACT` 改成绝对真路径 + 重启）后的外网验收：

| 探测 | 结果 |
| --- | --- |
| `POST /api/fnthink/poll` | **403 + `{"receipt":"rejected_unsigned"}`** ✅ 协议面活着 |
| `POST /api/fnthink/register` | **403 + 同形** ✅ |
| 大 body（>64 KiB） | **413 + `{}`** ✅ 契约里的体积闸生效 |
| `GET /api/fnthink/poll` | `Cannot GET /api/fnthink/poll` ✅ **前缀完整**（对比之前被削成 `/poll`） |
| `/server.js`、`/lib/store.js`、`/data/totp.json`、`/data/sessions.json`、`/index.html` | **全 404** ✅ 暴露已堵 |
| `/` | **302 → notice.fnthink.top** ✅ |
| `/health` | **200、零跳转、TLS 0** ✅ |
| `notice.* /health` 与 `/api/version/check` | 200 / `{"code":0,…}` ✅ 回归通过 |

⚠ **唯一没达标的一项：按 IP 的限流没被触发**。外网连发 31 次 `/register`（契约额度 `unauthenticatedPerMinute=30`），
第 31 次仍是 403 而不是 429。两种解释，**先分清再动手**：

- **① CF 打散（最可能）**：CF 用它自己的多个 IP 回源 ⇒ 我这 31 次请求落在几个不同的"每 IP 桶"里，谁都没到 30。
- **② 限流没生效**：服务端那条路没跑起来（可能性低 —— jest 有用例，且启动横幅会打印档位）。

**判定命令**（在服务器上直连上游，绕开 CF 与 Nginx，IP 恒为 127.0.0.1）：
```bash
for i in $(seq 1 31); do printf '%s ' "$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST http://127.0.0.1:3456/api/fnthink/register -H 'Content-Type: application/json' -d '{}')"; done; echo
# 期望：前 30 个 403、第 31 个 429（随后 1 分钟内继续 429）
```
出现 429 ⇒ 限流活着，"外网看不到 429"就是 CF 打散 ⇒ 必须做 XFF 修正（见下）。
全 403 ⇒ 限流真没生效，对着启动横幅查档位是不是没打出来。

⇒ 这就是"**CF 后面的真实 IP**"从一个理论问题变成实测后果的样子：源站看到的对端是 CF，限流/封锁/日志全部
记在 CF 的地址上。修法（源站反代段二选一）：
```nginx
proxy_set_header X-Forwarded-For $http_cf_connecting_ip;      # ① 覆盖 XFF（与 TRUST_PROXY=1 配套）
# ② 或 http 段 set_real_ip_from <CF 各段>; real_ip_header CF-Connecting-IP; 再把 XFF 设成 $remote_addr
```
已挂 **#140**（含上面的判定与验收）。另：那次 `Set-Cookie: server_session_…` 的出处仍待确认（直连上游
`curl -sSI http://127.0.0.1:3456/health | grep -i set-cookie`：有输出=别的进程/无输出=CF 或源站 Nginx）。

**第十二轮：access log 证据（2026-09-28 深夜，维护者贴出 grep 输出）**

在 push 站点 access log 里 grep `server\.js|totp\.json|sessions\.json` 之后的四个结论：

| # | 日志事实 | 结论 |
| --- | --- | --- |
| ① | 23:14:15 `/server.js` **200**（1570B）；23:14:24 与 23:15:38 两次 `/data/totp.json` **200**（749B）；23:14:59 `/data/sessions.json` **200**（**2B**） | 暴露**确曾被公网拉走**；23:25:03 起同批路径全 **404** ⇒ 兜底生效后再无成功访问 |
| ② | 来源 IP 全部落在 CF 段（172.70 / 172.64 / 162.158 / 172.71 / 172.68 / 141.101 …），UA 全部 `curl/8.21.0` | 与探测的时间/手法吻合 ⇒ **没有陌生第三方迹象**（边界：以这份日志的证据范围为限） |
| ③ | `sessions.json` 2 字节 = 空表 `{}` | **无活跃会话泄露**（没有可被复用的会话） |
| ④ | `totp.json` 749B 是密文（TOTP secret + 恢复码哈希），解密要 `.env` 的 `ENCRYPTION_KEY`，而 `.env` 从未出现在成功下载里；`server.js` 是 MIT 开源的源码 | 泄露物单独不可用（密文 ≠ secret；源码 ≠ 秘密） |

⇒ 这份日志同时是 **#140 的实锤**：源站看到的对端**全是 CF 地址**——这正是"外网连发 31 次没触发 429"的机制
（每个 CF 回源 IP 各记一个"每 IP 桶"，31 次被拆散，谁都没到 30）。判定命令与修法见上一节。

**#139 处置：按上述证据收窄为两档（待维护者选）**

- **最小档（推荐）**：不轮换。依据是 ②③④——没有第三方迹象、没有会话可复用、密文与源码单独都不可用。
- **保守档**：① 换 `ADMIN_TOKEN_HASH`（生成命令在 `server/.env.example`）；② 删 `server/data/totp.json`
  后重启（管理面回到未绑定状态，重新扫码绑 2FA；旧恢复码一并作废）；③ 确认 `sessions.json` 仍为空表。
  成本是管理面重新配置一次；纯为"睡得着"做它不必要，但也没害处。

**第十三轮：大陆域名 `push.fnthink.com` 已上线（2026-09-29 外网实测，按 `server/README.md` 第 5 步那 5 条照跑）**

> 这一轮推翻了本节此前两处的记录（8.4 的"`.com` 未部署"、8.0 快照的同源说法）。
> 探测从外网做，本机 `--ssl-no-revoke`（schannel 吊销检查，与服务器无关）。

| 探测 | 结果 | 判定 |
| --- | --- | --- |
| DNS `push.fnthink.com` | CNAME → `*.eo.dnse1.com`（**腾讯云 EdgeOne**，不是 CF）；实测对端 `113.142.27.122`（电信），另有 AAAA `240e:bf:c800:2915::45` | ✅ 已解析；⚠ 与 `.top` 不是同一个 CDN |
| TLS | 握手通过（`ssl_verify=0`）；`CN=fnthink.com`，SAN `*.fnthink.com, fnthink.com`，Let's Encrypt，**notAfter 2026-11-22** | ✅ 通配符覆盖到了；⚠ 到期见 8.4 |
| `POST /api/fnthink/{message,poll,ack,register,pair-arm,pair,pair-confirm}`（`-d '{}'`） | **七条一律 403 + `{"receipt":"rejected_unsigned"}`** | ✅ 协议面活着，**前缀没被削**（对比第十一轮之前那批 `Cannot POST /poll`） |
| `GET /api/fnthink/poll` | 404 + Express 的 `Cannot GET /api/fnthink/poll` | ✅ 路径**完整**到达上游（只挂 POST，符合设计） |
| 大 body：70010 字节 → `POST /api/fnthink/poll` | **413 且 body 是 `{}`**，`content-type: application/json` | ✅ 体积闸在服务端（不是 Nginx 的 HTML 413）；对照 60000 字节 → 403 ⇒ 闸门确实卡在 64 KiB 上 |
| `POST /api/admin/login`、`GET /admin.html` | 404 / 404 | ✅ 管理面不从这里进 |
| `/server.js` `/lib/store.js` `/lib/routes/auth.js` `/data/totp.json` `/data/sessions.json` `/package.json` `/.env` | **七条一律 404** | ✅ 暴露红线守住了（`.top` 上这批曾是真的 200，见第十二轮日志证据） |
| `/` | **302 → `https://notice.fnthink.top/`**（跟随后 200，一跳、不成环） | ✅ 就是 8.4「根路径要有点内容」推荐的那条 `location = /` |
| `/health` | **200 `{"status":"ok",…}`、零跳转**；两次都是 `EO-Cache-Status: MISS` + `Cache-Control: no-cache` | ✅ **真回源**，不是边缘缓存造成的假绿 |
| `http://` 80 端口 | **302 → https** | ⚠ 与 8.4 写的 `rewrite … permanent`（301）**差一拍**：这一跳由 EdgeOne 先代劳了。功能等价（明文进不来），但**别把这条 302 当成"源站 nginx 没配好"去修** —— 它到不了源站 |
| `notice.fnthink.top/health` + `/api/version/check` | 200 / `code=0, latestVersion=1.5.76, latestBuild=116` | ✅ 更新通道回归通过（加 `.com` 没连累它） |
| `Set-Cookie: server_session_…` | `.com` 上**同样出现**，两次同值；源站代码 grep 无 `server_session`/`res.cookie` | ⚠ 出处仍未定死（第十一轮那条待办**没关掉**）：一锤定音还是那句 `curl -sSI http://127.0.0.1:3456/health \| grep -i set-cookie`。现在只能说**不是 Node 应用发的**，至于是 CDN 还是源站 nginx，这份证据分不出来 |

⚠ **本机跑第 5 条那个大 body 命令会失败**（`Argument list too long`）—— README 写的是内联 `-d "{\"pad\":\"$(…)\"}"`，
在 Windows/git-bash 上命令行长度先撞上。等价写法（**别改 README，那是给 Linux 运维看的**）：
```bash
{ printf '{"pad":"'; head -c 70000 /dev/zero | tr '\0' 'a'; printf '"}'; } > /tmp/pad.json
curl -sS --ssl-no-revoke -w '\ncode=%{http_code}\n' -X POST https://push.fnthink.com/api/fnthink/poll \
     -H 'Content-Type: application/json' --data-binary @/tmp/pad.json      # 期望 413 + {}
```

**本轮补测的两条（8.8 那份清单原本只在 `.top` 上跑过）**

| 探测 | 结果 | 判定 |
| --- | --- | --- |
| `POST /api/fnthink/poll` 带外来 `Origin: https://example.org` | 403 `{"receipt":"rejected_unsigned"}`，响应里**没有** `Access-Control-Allow-Origin` | ✅ 与 `server/lib/app.js:38` 那段 CORS 对得上：未知来源走 `callback(null, false)` ⇒ **不发 ACAO**（浏览器读不到），但请求本身继续往下走，所以回执仍是协议形状。CORS 默认白名单在 `.com` 上生效 |
| `/apks/`、`/public/`、`/public/admin.html` | 一律 404 | ✅ 推送域名不服务静态（8.8 那条 `apks` 检查在 `.com` 上同样成立） |

⚠ **#140 在 `.com` 上不许照抄 CF 那一行的原因**（这条是**推理，未实测**）：链路是
`client → EdgeOne → 源站 nginx → node`，而 `trust proxy` 设成几、加上链路上**有几个角色在追加 XFF**，
共同决定 `req.ip` 落到谁身上。代码默认是 `TRUST_PROXY ?? 0`（`app.js:30`）= **完全不信代理** ⇒ `req.ip` 就是直连对端 = 边缘 IP；
线上 `.env` 实际设成几我没看到（那台机器上的东西）。而 nginx 那条 `$proxy_add_x_forwarded_for` **一定会追加**它看到的对端，
EdgeOne 自己是追加还是覆盖 XFF 决定最后一串长什么样 —— 两种情况都会让"设成 1"取到错的对象。
⇒ **动作顺序**：先在源站打一次真实收到的 `X-Forwarded-For` 与 `req.ip`（access log 加 `$http_x_forwarded_for` 就够），
**确认它是真实客户端还是边缘 IP，再决定设 `TRUST_PROXY=几` 还是改用 `real_ip_header`**；
`.top`（CF）与 `.com`（EdgeOne）**分别做一遍**，别共用一次结论。

**这一轮没验、也不该由我从外网验的四条（照实登记，别当成"全绿"）**

1. **按 IP 的限流 / 真实客户端 IP（#140）**：我**故意没有从外网撞 429**。契约 `limits.unauthenticatedPerMinute=30` 是按 IP 计的，
   而 `.com` 在 EdgeOne 后面 ⇒ 我这 31 发极可能记在**某个边缘节点的桶**上，撞满会把共用该节点的真实用户一起卡住
   （这正是契约注释里点出的那个形状）。**判定只能在服务器上直连上游做**（8.11 那条 31 次循环），
   而且 `.top`（CF）与 `.com`（EdgeOne）**要各判定一次** —— 两把桶、两套回源地址。
2. **验签全链路**（`register→pair→message→poll→ack`）：需要设备端私钥，且会在生产 `data/` 里落下真实设备记录。
   我没做。要做请明确授权（并事先想好这条测试设备怎么清掉）。
3. **IPv6**：有 AAAA 记录，但本机无 v6 路由（`curl -6` 直接解析失败）⇒ **未证可达**，既不等于通也不等于不通。
4. **3456 是否对公网裸露**：要从外部扫 `http://<服务器IP>:3456/admin.html` 才算（8.6 第 1 项）。本机测不了。

### 8.10 面板环境排障

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 502 Bad Gateway | Node 未起 / 端口不符 | Node 项目日志、`pm2 logs update-server` |
| 站点 404 | 反代未配 / 域名未绑到该站点 | 8.3 / 8.4 |
| 进程反复重启，日志"密钥未配置" | 运行目录不对 ⇒ `.env` 未读 | 8.5 |
| 证书申请失败 | 解析未生效 / 80 被占 / 站点未绑该域名 | 检查 DNS 与端口占用 |
| `duplicate server_name` | 手工 conf 与宝塔 conf 同时存在 | 8.0，二者留一 |
| 全员 429 | 反代共用出口 + `TRUST_PROXY` 未设 | `.env` 设 `TRUST_PROXY=1` 并重启 |
| 改动只在一个推送域名上生效 | `.top` 与 `.com` 可能分属两个站点 / 两份边缘配置（前面还是两个 CDN：CF 与 EdgeOne） | 8.4「是不是两个站点」、8.9 第十三轮 |
| 客户端"网络明明好的却连不上"，且只在大陆 | 切到了 mainland 端点，而**边缘证书到期**（通配符，2026-11-22） | 8.4 第 2 条待确认项 |

---

### 8.11 这批（A4 突增告警）上传时要带的东西

**新增两个服务端文件**：`lib/fnthink/anomaly.js`（内存环本体）、`lib/routes/alerts.js`（管理面读取口）。
它们都在 `server/` 里，整目录上传自然带上 —— 真正要当心的是下面这条。

⚠ **这一批的契约改了（新增顶层 `alerts` 段），所以 `protocol/fnthink-v1.json` 必须与本批代码一起上传。**
不一起传的表现：`/api/fnthink/*` 全部 503，其余一切正常。日志第一屏会说破是哪一种：

| 日志那行 | 含义 | 动作 |
| --- | --- | --- |
| `读不到契约文件 …` | 文件真不在 | 传契约 / 改 `FNTHINK_CONTRACT` |
| `契约文件在、也能解析，但内容缺这台服务端要读的数` | 代码本批、契约上一批 | **只补传契约**，`.env` 不用动 |

（这一批顺手修了一处不一致：以前"旧契约配新代码"走的是**崩在启动**，会把 `/api/version` 一起拖死；
现在它归入"可降级"那一类，只降级 `/api/fnthink` 这一段。这条与本仓文档一直写的口径对齐了。）

**验收（两条命令，一次同时把 #140 的判定做完）**：

```bash
# ① 服务器上直连上游，绕开 CF 与 Nginx（IP 恒为 127.0.0.1）
for i in $(seq 1 31); do printf '%s ' "$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST http://127.0.0.1:3456/api/fnthink/register -H 'Content-Type: application/json' -d '{}')"; done; echo
#   期望：前 30 个 403、第 31 个 429 ⇒ 限流活着（"外网看不到 429"就是 CF 打散，见 #140）
#   全 403 ⇒ 限流真没生效，先对着启动横幅查档位

# ② 读告警（登录拿 sessionId）
SESSION=$(curl -s -X POST http://127.0.0.1:3456/api/admin/login -H 'Content-Type: application/json' \
  -d '{"token":"<管理口令>"}' | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
curl -s http://127.0.0.1:3456/api/admin/fnthink/alerts -H "x-session-id: $SESSION"
#   期望 data.count ≥ 1，且有一条 {"subjectKind":"ip","subject":"127.0.0.1","kind":"register",
#   "window":"minute","outcome":"denied"}；near 那条（outcome=near）应该在第 15 发左右就出现过
#   count:0 ⇒ 说明②连的是另一个进程，或 ① 根本没打到这台（先看 ① 的 429）
```

读法提醒（这三条容易看错）：

- `persisted:false` ⇒ 告警只在当前进程内存里，**重启即空**；`count:0` 只代表"这个进程起来以后没触发"。
- `near` 与 `denied` 对同一主体是**两条**（处置不同：一个"快满了去看一眼"，一个"正在拒人"）。
- `times` 是累计次数：同一主体同一结论 300 秒内合并成一条，总数照加。
- 走公网读时 `subjectKind:"ip"` 的 `subject` 会是 CF 的回源地址（#140 未修前必然如此）。

### 8.12 运维处置口（A5：冻结 / 解冻 / 吊销 / 一键全部失效）

这批新增 `server/lib/routes/ops.js`，挂在 `/api/admin` 下（与登录、2FA、认证限流同一条链）。用法与判读写在
`server/README.md` 的「第 8 步」，这里只记部署侧真正会撞到的三件事：

**① 契约又改了（两处）**

- `revocation` 新增四个状态名键：`resumableStatus / frozenStatus / revokedStatus / afterRebuildStatus`。
  以前这四个名字在实现里写死了四处（登记初始档、解冻去处、全部失效跳过的那档、待重建写入的那档），
  那是第二份真值：契约加一档时它们不报错，只会静默地"这档没人认得，而记录照旧存在"。
- 新增顶层 `ops` 段：`listMaxRows` 与 `confirmationRequiredFor`。
  ⇒ **本批上传仍然必须带上 `protocol/fnthink-v1.json`**（同 8.11 那条）。

**② 这两个运维口各自只依赖自己要读的那一段**（这是刻意的，不是巧合）

契约缺 `alerts` 段时：`GET /api/admin/fnthink/alerts` 答 503，而 `GET /api/admin/fnthink/devices` 与冻结/吊销
照旧能用 —— 因为后者读的是 `revocation` + `ops` 段。运维在"协议面因为一份旧契约起不来"的时刻，
最需要的恰恰是还能把某台设备冻住。**如果哪天这两个口一起挂，那说明有人在模块顶层读了整个契约。**

⚠ 这一条本片是真踩到的：`ops.js` 最初在模块顶层 `loadContract()`，结果 require 链在 `app.js` 那段降级
try **之外**抛 ENOENT ⇒ 整台服务起不来、`/api/version` 一起挂 —— 被既有用例
「契约文件找不到 ⇒ `/api/fnthink` 明确 503 而 `/api/version` 照常 200」当场抓住。**新增会读契约的模块时，
先问一句：它读契约的时机在不在那段 try 里面。**

**③ 确认压在哪一类动作上（改之前先想清楚）**

| 动作 | 要 `confirm:true` | 为什么 |
| --- | --- | --- |
| freeze / resume | 否 | 随时可解、记录与公钥都留着、不丢数据 |
| revoke / revokeAll / rebuildInvalidation | 是 | 对方必须重新配对，误点撤销不了 |

判据是"误点之后能不能原地撤销"，**不是**"看起来严重不严重"。把 `freeze` 也压进确认名单会让运维学会
不看框直接点，那才是真正的危险；而 `massRevokeSupported=true` 却不要求确认，等于把一整个设备群的
失联挂在一次点击上 —— 这两条都由 Dart `validate()` 交叉钉住（改契约改不动它）。

**验收**（服务器上直连上游即可，不走 CF）：

```bash
SESSION=$(curl -s -X POST http://127.0.0.1:3456/api/admin/login -H 'Content-Type: application/json' \
  -d '{"token":"<管理口令>"}' | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
curl -s http://127.0.0.1:3456/api/admin/fnthink/devices -H "x-session-id: $SESSION"
#   期望 code:0，data.statuses 覆盖契约每一档，data.truncated 明确说出有没有列全
curl -s -X POST http://127.0.0.1:3456/api/admin/fnthink/devices/revoke \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' -d '{"addressCode":"<某台>"}'
#   期望 400 且 message 提到 confirm；紧接着再读一次列表，那台的 status **不该变**
```

⚠ 端点（endpoint）那一侧的"单独吊销"（T31 记的 ②）**没有**放在这批：现在还没有任何公网流量入口会去读
端点状态，先做一个入口就是造一个"看着能用其实不影响任何行为"的摆设。它跟 T39/T40 的端点形态同批落地。

---

### 8.13 T38 端点这一批：做到哪儿、没做到哪儿

改到的文件：`lib/fnthink/devicestore.js`（端点函数整组重写）、`lib/routes/ops.js`（多两个口）、契约新增顶层
`endpoint` 段（`ops.deviceListMax` 同时改名成 `ops.listMaxRows`，因为它管的是"一页列表"而不是某一张表）。

**这一批只到"存储层 + 运维可见"**：现在**没有任何公网 URL 会读端点表** —— 第三方能推的那两种形态（路径段带口令的
GET、POST + Bearer）在下一批。所以现在建了端点也不会"就能推"，别按"配好了为什么不响"去查。

管理面两个新口（都在 `/api/admin` 那条鉴权 + 认证限流链后面）：

```bash
SESSION=$(curl -s -X POST http://127.0.0.1:3456/api/admin/login -H 'Content-Type: application/json' \
  -d '{"token":"<管理口令>"}' | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
curl -s http://127.0.0.1:3456/api/admin/fnthink/endpoints -H "x-session-id: $SESSION"
#   期望 code:0；data.statuses 对**全表**计数（不是截断后那一页）；每条只有 11 个白名单键
#   ⚠ 响应里既没有明文口令也没有 secretDigest —— 摘要是可离线爆破的靶子，不该被端出去
curl -s -X POST http://127.0.0.1:3456/api/admin/fnthink/endpoints/revoke \
  -H "x-session-id: $SESSION" -H 'Content-Type: application/json' -d '{"endpointId":"e_xxx"}'
#   期望 400 且那个端点**仍然可用**（先写后判是这类接口最坏的顺序）；带 "confirm":true 才生效
```

四条判据值得单独记（它们决定下一批接上形态时会不会出事）：

1. **鉴权只看 `status === usableStatus`（白名单式）**，不是"是不是 revoked" —— 与 T31 那次写反的是同一类错误。
2. **轮换有宽限期**（契约 `endpoint.rotation.graceSeconds`，上限一天）：没有它，换口令那一刻所有集成同时失败，
   后果不是不便，是"从此没人换口令"。
3. **两个上限都只拒新的**：挤掉一个已有端点 = 某台 NAS 的定时任务从此静默失效。
4. **调用日志只存元数据**（时间/来源/结论）且有界：正文进日志会直接推翻 `privacy.auditStoresMetadataOnly`；
   而"记 url"等于把口令写进日志（口令就在路径段里）—— 这两条都由 validate 钉住，不靠自觉。

⚠ 上传照旧：**这批契约又改了**（`endpoint` 段 + `ops.listMaxRows` 改名）⇒ `server/` 与
`protocol/fnthink-v1.json` 必须同批；只传代码会让协议面降级 503（日志点名"内容缺这台服务端要读的数"），
两个域名（`.top` / `.com`）各自都要换。

### 8.14 端点收单这一批（T39–T41 + 管理面写入口）：带什么、怎么验

**这一批必须连契约一起上传**，否则不是崩、是"只有那一段降级"：

- 要传的东西：`server/` 整目录（**含新文件 `server/lib/fnthink/endpointintake.js`**）
  + 同一批的 `protocol/fnthink-v1.json`（新增了顶层 `endpoint.ingress` 段；随后 #126 第二片又加了
    `transport.apiPaths` —— 设备面七条 URL 的唯一出处，**服务端不读它**，所以只更代码不更契约也不会坏，
    但客户端与反代配置要以它为准，别照着旧文档抄路径）。
- 只传代码、契约还是上一批 ⇒ 启动日志会打两行并把 `/api/fnthink` 降级成 503：
  `[fnthink] 协议入口没有起来…` 与 `[fnthink] 契约文件在、也能解析，但内容缺这台服务端要读的数…`。
  `/api/version` 与管理后台**照常活着**（这是 A4 那次专门修的方向）。
  判定命令与两种 503 的区分见 8.11；这里不重复。
- ⚠ 禁覆盖 `data/`、`.env`、`node_modules/`；同步时禁 `--delete`。

#### 第 1 步：确认这一面真的起来了（三条新 URL 进了横幅）

```bash
cd <你的部署目录> && node server.js 2>&1 | grep "/api/fnthink/p"
```

期望输出三行，且每行后面跟的是"按端点 …（口令验完后由端点收单计，不占 IP 那三档）"：

```
  GET  /api/fnthink/p/:endpointId/:secret  - 按端点 15/分钟 · 500/天（…）
  POST /api/fnthink/p/:endpointId/:secret  - 按端点 15/分钟 · 500/天（…）
  POST /api/fnthink/p/:endpointId           - 按端点 15/分钟 · 500/天（…）
```

失败判定：看到 `未登记 ⇒ 按最紧的一档…` ⇒ 那就是横幅与限流器对同一个路径算出了两个 kind，
本批已修（`endpointKindOf` 认任意位置的 `p` 段）；若还出现，说明 `server/lib/fnthink/ratelimit.js`
没传上去。

#### 第 2 步：铸一条口令（管理面，owner 必须是已登记的设备）

```bash
curl -sS -X POST "http://127.0.0.1:3000/api/admin/fnthink/endpoints/create" \
  -H "x-session-id: $SESSION" -H "Content-Type: application/json" \
  -d '{"owner":"<那台设备的地址码>","name":"家里 NAS"}'
```

期望：`{"code":0,"data":{"action":"createEndpoint","affected":1,"endpoint":{...},"secret":"XXXX…","secretShownOnce":true}}`

失败判定（都是 400，含义完全不同）：

| 回什么 | 含义 | 下一步 |
| --- | --- | --- |
| `owner 必须是一个合法的地址码` | 抄错/粘了带空格的串 | 从 App 里"我的设备"复制地址码 |
| `这台设备还没登记：…` | 那台设备从没连上这台实例 | 先在 App 里连上（`/register`），再来铸 |
| `这台设备的可用端点已达上限 10` | 每台默认最多 10 条 | 吊销不要的，**已有的一条都不会被挤掉** |
| `401` | 会话过期（TTL 24h，不滑动） | 重新 `POST /api/admin/login` |

⚠ `secret` **只在这次响应里出现一次**。表里存的是摘要，任何接口都拿不回明文 —— 现在不落盘，
待会儿只能轮换（轮换会让第三方那一份改掉）。

#### 第 3 步：推一发，按结论表判（这一面的三种失败是故意同形的）

```bash
# 走 https（生产就该这样）
curl -sS -o /dev/null -w "%{http_code}\n" -X POST "https://<你的域名>/api/fnthink/p/<endpointId>" \
  -H "Authorization: Bearer <secret>" -H "Content-Type: application/json" \
  -d '{"title":"备份","body":"第 3 盘完成了"}'
```

| 看到 | 结论 | 怎么继续查 |
| --- | --- | --- |
| `202` | 已排队，设备下次 poll 就取走 | 完成 |
| `401` 且 body 是 `{}` | **端点不存在 / 口令不对 / 来源 IP 不在白名单** —— 三者逐字节相同，不是服务端坏了 | 只能看端点调用日志（第 4 步），响应体里没有信息 |
| `403` 且 body 是 `{}` | 明文 http 且没开逃生阀 | 走 https；只在确实要内网直连时临时 `FNTHINK_ALLOW_INSECURE_ENDPOINT=1`（改完 `.env` 要重启），验完关掉 |
| `403` 且 `{"receipt":"rejected_capability"}` | 超出能力边界（`type=action`、`level` 高于 L1、带了 `item`） | 让第三方只发标题 + 正文 |
| `405` 且 `{}` | 这条端点是"仅 POST"，而它被 GET 打了 | 用 POST + Bearer，或按第 5 步把 `postOnly` 关掉 |
| `400` 且 `{}` | 标题与正文都空，或超过长度上限（**不会被截断后收下**） | 让第三方改内容；上限见契约 `endpoint.ingress.maxTitleChars/maxBodyChars` |
| `429` + `Retry-After` | 这条端点的 15/分或 500/天到顶 | 看告警口（第 4 步），配额按端点计，别的端点不受影响 |

#### 第 4 步：排查看这里 —— 调用日志与告警（响应体故意不说的事，这里都有）

```bash
curl -sS "http://127.0.0.1:3000/api/admin/fnthink/endpoints" -H "x-session-id: $SESSION"
```

期望：每条端点带 `calls`，每项只有 `at` / `ip` / `outcome` 三个键。`outcome` 是运维词：
`queued` / `duplicate` / `rate_limited` / `rejected_ip` / `rejected_method` / `rejected_capability` /
`rejected_transport` / `empty_payload` / `payload_too_large` / `unbound_endpoint` / `unknown_endpoint`。

失败判定：`calls` 里出现了 `body`、`title`、`secret`、`path`、`url` 中任何一个 ⇒ 立刻停手，
那是契约 `endpoint.callLog.fields` 被改动过（validate 会拦，但别指望它在你手改文件后还响）。

告警口同样能看到这一类（`subjectKind=endpoint`，主键是端点 id 而不是 IP）：

```bash
curl -sS "http://127.0.0.1:3000/api/admin/fnthink/alerts" -H "x-session-id: $SESSION"
```

#### 第 5 步：改策略与轮换（各一条 curl）

```bash
# 允许 GET 形态（口令会进 URL，谨慎）
curl -sS -X POST "http://127.0.0.1:3000/api/admin/fnthink/endpoints/policy" \
  -H "x-session-id: $SESSION" -H "Content-Type: application/json" \
  -d '{"endpointId":"<id>","postOnly":false}'
# 换一把新口令（不要 confirm：旧的那把在宽限期内照样能用）
curl -sS -X POST "http://127.0.0.1:3000/api/admin/fnthink/endpoints/rotate" \
  -H "x-session-id: $SESSION" -H "Content-Type: application/json" -d '{"endpointId":"<id>"}'
```

期望：`policy` 回 200 + 改后的 `endpoint`；`rotate` 回 200 + `secret`（一次性）
+ `graceSeconds` + `oldSecretValidUntil`（毫秒时间戳，`Date(oldSecretValidUntil)` 读成人话）。
在 `oldSecretValidUntil` 之前，**旧口令与新口令都能推**；过了那个点旧的不再多一条命中。

失败判定：`这个端点已经是「revoked」那一档` ⇒ 已吊销的不许被轮换或改设置"救活"，要恢复就新建一条
（旧那条的调用日志与创建时间属于那条记录，不该被继承）。

#### 第 6 步：access log 里不许有口令

契约 `transport.secretPlacement = path_segment` + `accessLogRedactPathPattern = /api/fnthink/p/`：
口令在路径段里，所以**脱敏必须覆盖这个前缀**，否则它会在 access log 里长期留存。

```bash
grep -m3 "/api/fnthink/p/" <你的站点 access log>
```

期望：路径里那段口令已被替换（或被整条 redact）。若看到明文口令 ⇒ 按 8.9 那条 `location` 级
日志格式改；宝塔面板侧见 8.10。

#### 这批改变了什么（用户可感知的差别）

- 公网面**多了三条 URL**（`GET/POST /api/fnthink/p/…`）。它们不占 `limits` 那三档 IP 额度，
  但仍受层 1 那道洪水闸（`RATE_LIMIT_FNTHINK_MAX`，每 IP）管着。
- 没有任何自动创建：不铸口令，这三条 URL 一律 `401 {}`，与"口令错"同形。
- 端点推来的消息只产 L1 通知，走的是与设备签名消息同一条投递状态机（排队、补发、到期删正文）。

#### 回滚

纯增量：回滚代码时**同时把契约回滚到同一批**（反过来不成立 —— 新代码配旧契约只降级这一段，
旧代码配新契约不受影响）。`data/fnthink_endpoints.json` 可以留着：没有读它的代码时它不生效，
而删掉它会让"回滚再滚回来"时所有口令作废。

---

### 8.15 投递状态读口（T45：只读、只在管理面）

改到的文件：`lib/fnthink/delivery.js`（到期算式抽成 `retentionDeadline`，`isExpired` 改用它，
"判过没过"与"给人看还剩多久"从此是同一个数；推进一步的结果里带上**是哪个事件**挪走的）、
`lib/fnthink/messagestore.js`（新增投影 `publicMessage` + 留痕 `appendTrail`）、
`lib/routes/ops.js`（多一个 GET 口）、`protocol/fnthink-v1.json`（`retention.storedFields` 多两列
`trail` / `trailDropped`，新增 `retention.auditTrail` 段给出上限与留痕字段名单）。
⚠ **这一批改了契约 ⇒ 上传 `server/` 必须连同批 `protocol/fnthink-v1.json` 一起传**（禁覆盖 `data/`、`.env`）。

```bash
SESSION=$(curl -s -X POST http://127.0.0.1:3456/api/admin/login -H 'Content-Type: application/json' \
  -d '{"token":"<管理口令>"}' | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
curl -sS "http://127.0.0.1:3456/api/admin/fnthink/messages" -H "x-session-id: $SESSION"
#   期望 code:0；data.states 对**全表**按契约 delivery.states 逐档计数（不受筛选影响）；
#   data.truncated 明确说出有没有列全；limit 上限 = 契约 ops.listMaxRows（给多大都夹）
curl -sS "http://127.0.0.1:3456/api/admin/fnthink/messages?state=waiting_online&limit=20" \
  -H "x-session-id: $SESSION"
```

期望每行只有这些键：`messageId sender device type item state terminal attempts queuedAt updatedAt
expiresAt receipt receiptSentAt hasBody targetLastSeenAt trail trailDropped`。

`trail` 是投递时间线，每条是 `{state, at, event}`（"这一步被哪个事件挪到了哪个状态、发生在什么时候"）：

- `trail: [...]` 被推进几步就是几条，**被忽略的事件不入列**（迟到的 ack 什么都没发生）；
- `trail: []` 说的是"这条从初态一步没走过"；
- `trail: null` 说的是"这一行比留痕那一列更早"——**升级之前落盘的那些消息没有历史可看**，
  这不是坏了，是那之前没有这一列。视图上把这两种混成一句话，运维就会去查一个不存在的 bug。
- `trailDropped` 是按契约 `retention.auditTrail.maxPerMessage` 从头部裁掉的条数：
  一条 `waiting_online` 的消息每次 poll 都会被推进一次，7 天能积累成千上万条，所以留痕必须有界，
  而**裁掉多少要留下计数**（悄悄裁与悄悄丢在运维眼里是同一个错）。

**失败判定**：
- `?state=<不认识的一档>` 回 400 而不是空列表 ⇒ 正常。回 200 空列表才是问题（把打错的档位读成"这一档没有"）。
- `?device=<一串垃圾>` 同样回 400：拿它当键去筛，"筛出一条都没有"与"这台没发过消息"就同形了。
- 未登录 401：这份视图知道**谁在给谁发消息**（地址码 + 类型 + 时间），它不是开放口。
- 响应里出现 `body` / 密信封 / `dedupeIdDigest` ⇒ 立刻当成安全事件处理：那推翻的是
  `privacy.auditStoresMetadataOnly`，不是"多了一个字段"。盘上加密、接口端出明文，等于把 7 天保留期
  变成"任何时候都能从管理面捞一遍正文"。

⚠ **留痕从这一批才开始有**：升级之前落盘的那些年月里的消息永远只会显示 `trail:null`，
"什么时候下发过一次"这种问题对它们无解（不是查代码，是那之前没人记）。`hasBody` 那一列反过来一直有用：
**终态却有正文**就是"每个终态都释放正文"那条不变量在真实盘上坏了的痕迹（单测证不了生产数据没漏）。

回滚：`data/fnthink_messages.json` 里多出来的 `trail` / `trailDropped` 两列**可以被旧代码忽略**
（旧投影不读它们，也没有代码会写它们），所以回滚 `server/` 不会崩。但**新代码配旧契约不行**：
`retention.auditTrail` 拿不到 ⇒ 第一次推进留痕（poll 取货那一下）就抛 —— 收单还会 202，
取货开始 500，这个"前半能用后半炸"的形状很好认（`messagestore` 那里刻意不退回默认值）。所以这一批的两半（`server/` 与 `protocol/fnthink-v1.json`）要么一起上，
要么一起回 —— 设备侧同理：新 APK 的 validate 会要求契约里有 `trail`，配旧契约的报错是**故意**的。

#### 这批改变了什么（用户可感知的差别）

零。没有新公网 URL，设备侧行为一字未动 —— 多出来的只有运维能读的一条管理面 GET。


---

## 9. 变更记录

- 2026-09-29（第六版）：8.15 续 —— **投递时间线（T45 第二片）落地**：每行多出 `trail`（`{state, at, event}`
  的有界列表）与 `trailDropped`。`trail:null` 说的是"这一行比留痕那一列更早"，与 `[]`（一步没走过）
  是两句话。**这一批改了契约**（`retention.storedFields` 多两列 + 新增 `retention.auditTrail` 段），
  所以 `server/` 与 `protocol/fnthink-v1.json` 必须同批上；新代码配旧契约的形状是"收单还 202、
  poll 取货开始 500"。留痕的界从契约读，取不到就抛（不退回默认值 —— 没界的日志就是攻击者驱动的存储）。
- 2026-09-29（第五版）：新增 8.15「投递状态读口」—— 管理面多一条只读 GET `/api/admin/fnthink/messages`
  （按契约 `delivery.states` 逐档计数、`state` / `device` 两个筛、`limit` 夹在 `ops.listMaxRows`）。
  **契约与协议面没动 ⇒ 这一批只上传 `server/`**。一行投递记录里没有正文、没有密信封、没有 dedupe 摘要；
  也**还没有时间线**（表里今日只有当前态 + 两个时间戳），那是下一片。
- 2026-09-29（第四版）：新增 8.14「端点收单这一批带什么、怎么验」—— T39–T41 的两条收单 URL（GET 口令在路径段、
  POST + Bearer）与管理面写入口（create / rotate / policy）都在这一批；**必须连 `protocol/fnthink-v1.json` 一起上传**
  （新增了 `endpoint.ingress` 段，只传代码会把 `/api/fnthink` 整段降级成 503，而更新服务与管理后台照常）；
  验收按 6 步走（横幅三条 → 铸口令 → 推一发按结论表判 → 调用日志与告警 → 策略与轮换 → access log 搜口令）。
- 2026-09-29（第三版）：新增 8.13「T38 端点这一批做到哪儿」—— 契约新增顶层 `endpoint` 段（`ops.deviceListMax`
  改名 `ops.listMaxRows`）；明确**这批没有公网入口**（第三方能推的两种形态在下一批），管理面加了
  只读列表与吊销两条口；记下四条会在下一批决定成败的判据（白名单式状态判定、轮换宽限、只拒新的、日志只存元数据）。

- 2026-09-29（第二版）：新增 8.12「运维处置口（A5）」—— 契约 `revocation` 补四个状态名键（实现里以前
  写死四处）、新增顶层 `ops` 段（列表上限 + 需要确认的动作名单）；记下"运维口各自只依赖自己要读的
  那一段"这个设计（缺 `alerts` ⇒ 告警 503 而冻结仍可用），以及本片实际踩到的那次：新模块在**顶层**
  读契约会让"只上传 server/"重新变成整台服务起不来，被既有的降级用例当场抓住。

- 2026-09-29（第二版）：**大陆域名 `push.fnthink.com` 已上线**（推翻本档此前两处"未部署"的记录）。新增 8.9 第十三轮：
  按 `server/README.md` 第 5 步那 5 条照跑 + 暴露七条 + 配对自检 —— 七条路由一律 403 `rejected_unsigned`、
  大 body 413+`{}`（60000 字节对照是 403）、`GET` 回 `Cannot GET /api/fnthink/poll`（前缀完整）、暴露七条一律 404、
  `/` 302 跳主站、`/health` 200 且 `EO-Cache-Status: MISS`（真回源）、`notice.*` 回归通过。
  **两条新事实写进 8.0 与 8.4**：① `.top` 在 Cloudflare、`.com` 在腾讯云 EdgeOne ⇒ #140 要各判定各修；
  ② 边缘证书是 `*.fnthink.com` 通配符（Let's Encrypt），**2026-11-22 到期**，续期路径待确认。
  ⚠ 同时如实登记**没验的四条**（按 IP 限流/真实 IP —— 故意不从外网撞 429，见第十三轮说明；验签全链路；IPv6；3456 是否裸露）。
  #137 由此收口（走的是当时列的第 1 个选择，契约不动）；8.8 加"两个推送域名各跑一遍"；排障表加两行。
  本机侧一条实操坑：README 那条内联 70000 字节的 `-d` 在 Windows/git-bash 上先撞 `Argument list too long`，改用 `--data-binary @file`。
- 2026-09-29：新增 8.11「A4 突增告警这批要带什么」—— 契约新增 `alerts` 段 ⇒ **本批必须连契约一起上传**，
  否则 `/api/fnthink/*` 全 503（日志现在分两种原因点名）；同批修掉"旧契约配新代码会崩在启动、连带拖死
  `/api/version`"那处不一致（新增第四类可降级标记 `FNTHINK_CONTRACT_SHAPE`）。验收两条命令一次跑完
  （连发 31 次判定限流 + 读告警列表），顺带把 #140 的判定并进来。

- 2026-09-28（第四版）：8.9 补「第十二轮：access log 证据」—— 暴露确曾被公网拉走（四条 200 早于堵塞，
  23:25 起全 404），但无陌生第三方迹象（全 CF 段 + `curl/8.21.0`）、`sessions.json` 是空表、
  `totp.json` 是密文、`server.js` 是开源源码；**#139 据此收窄为最小/保守两档**；
  同份日志实证 **#140**（源站对端全 CF 段 ⇒ 每 IP 桶被拆散）。
- 2026-09-28（第三版）：新增 8.9「上线核查（外部探测）」—— 从外网实测 `push.fnthink.top`：
  DNS 走 CF、TLS 通、`notice.*` 更新通道回归通过，但 **push 站点的 `proxy_pass` 尾斜杠把
  `/api/fnthink/` 前缀吃掉了**（三处实证：上游回 `Cannot POST /poll` 等），另记两条待落实
  （`location / { return 404; }` 未生效、CF 后面的真实 IP）。原来是 8.9 的排障表顺延为 8.10。
- 2026-09-28（第二版）：新增第 8 章「宝塔面板部署（BT Panel）」，含与已在线的 `notice.*` 的关系（8.0）、
  推送站点只放两个 location、`map/log_format` 脱敏要放 `http` 段、运行目录与 `.env` 的坑、3456 不放行。
- 2026-09-28：首版。对应提交 `c42e154`→`0e8d520`→`2084f2c`→`247ba35`（README 去真实域名、加装章节、部署形态两章）与更早的 #130-A1/A2/A3（契约新增 `limits` 字段、改名两个键、加 413/400、加 `requestBodyMaxBytes`）。
- ⚠ 遗留：设备侧 fnthink 客户端（#126）未做；公网面上线后只有探针流量。
