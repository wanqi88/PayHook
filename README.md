# PayHook — ios-WeChat收款监控方案

基于 iOS Hook 技术的微信收款监听方案，自动匹配订单并回调商户，实现无人值守码支付。

## 系统概览

```
商户系统 ──→ API 创建订单 ──→ 用户扫码支付
                                    │
                             微信到账通知
                                    │
                         PayHook 插件检测收款
                                    │
                    上报后端 ──→ 按金额匹配订单 ──→ 回调商户
```

## 项目结构

```
.
├── PayHook_iOS/                # iOS 插件源码 (theos)
│   ├── Tweak.x                 # 主控 + 6 组 CMessageMgr Hook + 四层收款识别
│   ├── XJPaymentXMLParser.m    # 微信支付 XML 深度解析 (wcpayinfo)
│   ├── XJRemoteConfig.m        # 远程配置热更新 (关键词/正则/白名单)
│   ├── XJPaySourceConfig.m     # 公众号白名单 NSSet 查找 (O(1))
│   ├── XJMessageDedup.m        # svrMsgId LRU 消息去重
│   ├── Makefile                # theos 编译配置
│   ├── build.sh                # 自动版本号递增构建
│   └── README.md
│
└── pay/                        # PHP 后端源码
    ├── api.php                 # API 路由 (创单/查单/监控上报/回调)
    ├── db.php                  # 数据库操作 (PDO, MySQL)
    ├── config.php              # 配置文件 + MD5 签名算法
    ├── pay.php                 # 用户支付页面 (收款码 + 金额 + JS 轮询)
    ├── admin.php               # 管理后台 (订单/收款/商户管理 + 统计)
    ├── init.php                # 部署初始化 (建表 + 默认商户 + 环境检查)
    └── check.php               # 订单状态 JSONP 轮询
```

## 工作流程

### 1. 创建订单

商户 POST 请求到 `api.php?action=order_create`：

```http
POST /api.php?action=order_create
Content-Type: application/x-www-form-urlencoded

merchant_id=M100001&out_trade_no=ORDER001&amount=0.50&sign=ABCD
```

返回支付链接，用户打开后看到微信收款码和精确金额。

### 2. 检测收款

PayHook 通过 CMessageMgr Hook 拦截微信消息，经过四层识别：

| 层级 | 方法 | 置信度 |
|------|------|--------|
| 1 | 公众号白名单匹配 | 高 |
| 2 | XML wcpayinfo 解析 | 高 |
| 3 | 关键词匹配 | 中 |
| 4 | 发送者模糊匹配 | 低 |

识别成功后提取金额（XML feedesc 优先），经过去重后 HTTP POST 上报到后端。

### 3. 订单匹配

后端收到监控上报后，按实付金额精确匹配待支付订单：

```sql
SELECT * FROM orders
WHERE pay_amount = ? AND status = 'created' AND expires_at > NOW()
ORDER BY created_at ASC LIMIT 1
```

匹配成功后自动 `markPaid`，并异步回调商户 `notify_url`，附带 MD5 签名供商户验签。

## iOS 插件安装

PayHook 编译产出 `.dylib` 动态库，注入微信 IPA 后安装即可使用，无需越狱。

### 方式一：巨魔永久签名 (TrollStore)



### 方式二：自签证书注入



### 使用方法

安装完成后，在微信 **我 → 设置** 页面**连点标题 5 次**，弹出 PayHook 控制面板，可查看运行统计、修改服务器地址、发送测试上报、查看最近收到的消息。

---

## 编译

### 环境要求

- macOS + Xcode（提供 iOS SDK）
- [theos](https://github.com/theos/theos) 安装于 `~/theos`

### 构建

```bash
cd PayHook_iOS
./build.sh
```

每次构建自动递增版本号，输出 `PayHook_v3.0.0-{N}.deb` 和 `PayHook_v3.0.0-{N}.dylib`。

---

## 后端部署

### 环境要求

- PHP 7.4+（需 pdo_mysql, curl, json, mbstring）
- MySQL / MariaDB

### 部署步骤

```bash
vim pay/config.php            # 修改 SITE_URL 和数据库连接
php pay/init.php              # 建表 + 创建默认商户
# 把微信收款码放到 pay/data/wechat_qr.png
# 配置 Nginx/Apache 网站根目录指向 pay/
```

### 关键配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `SITE_URL` | `http://pay.yzfaiu.xyz` | 站点访问地址 |
| `ORDER_EXPIRE_SECONDS` | `300` | 订单过期时间 (秒) |
| `MONITOR_DEDUP_SECONDS` | `30` | 监控端去重窗口 (秒) |

### 监控密钥

PayHook 使用 `monitor_secret` 字段验证身份，默认值 `mapay_monitor_2024`。可通过环境变量覆盖：

```bash
export MAPAY_MONITOR_SECRET="your_custom_secret"
```

---

## 控制面板

管理后台：`https://your-domain.com/admin.php`

- 订单列表：查看所有订单状态、金额、回调情况
- 收款记录：监控端上报的每一笔收款明细
- 商户管理：添加/管理商户及 API Key
- 统计面板：总订单数、已支付数、支付总额

## 作者

<table>
  <tr>
    <td align="center">
      <a href="https://github.com/yZFAIU">
        <img src="https://github.com/yZFAIU.png" width="60" height="60" style="border-radius:50%" alt="yZFAIU"/><br/>
        <b>yZFAIU</b>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/wanqi88">
        <img src="https://github.com/wanqi88.png" width="60" height="60" style="border-radius:50%" alt="wanqi88"/><br/>
        <b>wanqi88</b>
      </a>
    </td>
  </tr>
</table>

## License

MIT
