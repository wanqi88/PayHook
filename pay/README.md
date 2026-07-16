# 部署

## 快速开始

```bash
# 1. 编辑配置
vim config.php     # 修改 SITE_URL 和数据库连接

# 2. 初始化
php init.php       # 建表 + 创建默认商户

# 3. 上传收款码
cp wechat_qr.png data/wechat_qr.png
```

## API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `api.php?action=order_create` | POST | 创建订单 |
| `api.php?action=order_query` | POST | 查询订单 |
| `api.php?action=order_close` | POST | 关闭订单 |
| `api.php?action=monitor_report` | POST | 监控端上报收款 |
| `api.php?action=health` | GET | 健康检查 |
| `api.php?action=stats` | GET | 统计数据 |

## 数据库

- 数据库: `mapay`
- 表: `merchants` (商户), `orders` (订单), `payments` (收款记录), `monitor_logs` (监控日志)

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MAPAY_MONITOR_SECRET` | `mapay_monitor_2024` | 监控端验证密钥 |
