<?php
/**
 * MaPay 码支付 - 数据库操作
 * ==========================
 * MySQL 数据库，PDO 单例
 * 表: merchants, orders, payments, monitor_logs
 */

require_once __DIR__ . '/config.php';

class Database
{
    private static ?PDO $instance = null;

    public static function getInstance(): PDO
    {
        if (self::$instance !== null) {
            return self::$instance;
        }

        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            DB_HOST, DB_PORT, DB_NAME);

        self::$instance = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);

        return self::$instance;
    }

    /** 初始化所有表 */
    public static function initTables(): void
    {
        $db = self::getInstance();

        $sqls = [
            // 商户表
            "CREATE TABLE IF NOT EXISTS merchants (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                merchant_id VARCHAR(32) NOT NULL UNIQUE,
                merchant_name VARCHAR(128) NOT NULL DEFAULT '',
                api_key     VARCHAR(128) NOT NULL,
                callback_url VARCHAR(512) NOT NULL DEFAULT '',
                status      TINYINT NOT NULL DEFAULT 1 COMMENT '1=active 0=disabled',
                created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

            // 订单表
            "CREATE TABLE IF NOT EXISTS orders (
                id           INT AUTO_INCREMENT PRIMARY KEY,
                trade_no     VARCHAR(64) NOT NULL UNIQUE COMMENT '系统订单号',
                merchant_id  VARCHAR(32) NOT NULL,
                out_trade_no VARCHAR(128) NOT NULL COMMENT '商户订单号',
                amount       DECIMAL(10,2) NOT NULL COMMENT '请求金额',
                pay_amount   DECIMAL(10,2) NOT NULL COMMENT '实付金额(随机化)',
                title        VARCHAR(256) NOT NULL DEFAULT '',
                attach       VARCHAR(256) NOT NULL DEFAULT '',
                status       VARCHAR(20) NOT NULL DEFAULT 'created' COMMENT 'created|paid|expired|closed',
                pay_type     VARCHAR(20) NOT NULL DEFAULT 'wechat',
                client_ip    VARCHAR(45) NOT NULL DEFAULT '',
                notify_url   VARCHAR(512) NOT NULL DEFAULT '',
                notify_status VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT 'pending|success|failed',
                notify_count INT NOT NULL DEFAULT 0,
                paid_at      DATETIME NULL,
                expires_at   DATETIME NULL,
                created_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at   DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_merchant (merchant_id, out_trade_no),
                INDEX idx_status_amount (status, pay_amount),
                INDEX idx_expires (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

            // 收款记录表 (监控端上报)
            "CREATE TABLE IF NOT EXISTS payments (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                amount      DECIMAL(10,2) NOT NULL,
                pay_type    VARCHAR(20) NOT NULL DEFAULT 'wechat',
                raw_text    TEXT,
                trade_no    VARCHAR(64) NOT NULL DEFAULT '' COMMENT '匹配到的订单号',
                matched     TINYINT NOT NULL DEFAULT 0 COMMENT '0=未匹配 1=已匹配',
                monitor_id  VARCHAR(64) NOT NULL DEFAULT '',
                source      VARCHAR(64) NOT NULL DEFAULT '',
                client_ip   VARCHAR(45) NOT NULL DEFAULT '',
                created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_amount (amount),
                INDEX idx_matched (matched),
                INDEX idx_created (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

            // 监控端日志
            "CREATE TABLE IF NOT EXISTS monitor_logs (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                monitor_id  VARCHAR(64) NOT NULL,
                event       VARCHAR(128) NOT NULL,
                detail      TEXT,
                client_ip   VARCHAR(45) NOT NULL DEFAULT '',
                created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        ];

        foreach ($sqls as $sql) {
            $db->exec($sql);
        }
    }

    // ═══════════════════════════════════════════
    //  商户操作
    // ═══════════════════════════════════════════

    public static function getMerchant(string $merchantId): ?array
    {
        $db = self::getInstance();
        $stmt = $db->prepare('SELECT * FROM merchants WHERE merchant_id = ? AND status = 1');
        $stmt->execute([$merchantId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function listMerchants(int $limit = 100): array
    {
        $db = self::getInstance();
        return $db->query("SELECT * FROM merchants ORDER BY id DESC LIMIT {$limit}")->fetchAll();
    }

    public static function addMerchant(string $merchantId, string $name, string $apiKey, string $callbackUrl = ''): void
    {
        $db = self::getInstance();
        $stmt = $db->prepare('INSERT INTO merchants (merchant_id, merchant_name, api_key, callback_url) VALUES (?, ?, ?, ?)');
        $stmt->execute([$merchantId, $name, $apiKey, $callbackUrl]);
    }

    // ═══════════════════════════════════════════
    //  订单操作
    // ═══════════════════════════════════════════

    public static function createOrder(array $data): array
    {
        $db = self::getInstance();
        $stmt = $db->prepare(
            'INSERT INTO orders (trade_no, merchant_id, out_trade_no, amount, pay_amount, title, attach, status, pay_type, client_ip, notify_url, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, "created", ?, ?, ?, ?)'
        );
        $stmt->execute([
            $data['trade_no'],
            $data['merchant_id'],
            $data['out_trade_no'],
            $data['amount'],
            $data['pay_amount'],
            $data['title'],
            $data['attach'],
            $data['pay_type'] ?? 'wechat',
            $data['client_ip'],
            $data['notify_url'],
            $data['expires_at'],
        ]);
        return self::getOrder($data['trade_no']);
    }

    public static function getOrder(string $tradeNo): ?array
    {
        $db = self::getInstance();
        $stmt = $db->prepare('SELECT * FROM orders WHERE trade_no = ?');
        $stmt->execute([$tradeNo]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function getOrderByMerchantNo(string $merchantId, string $outTradeNo): ?array
    {
        $db = self::getInstance();
        $stmt = $db->prepare('SELECT * FROM orders WHERE merchant_id = ? AND out_trade_no = ? ORDER BY id DESC LIMIT 1');
        $stmt->execute([$merchantId, $outTradeNo]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /** 查找待支付且金额匹配的订单 */
    public static function findPendingByAmount(float $amount): ?array
    {
        $db = self::getInstance();
        $stmt = $db->prepare(
            'SELECT * FROM orders
             WHERE pay_amount = ? AND status = "created" AND expires_at > NOW()
             ORDER BY created_at ASC LIMIT 1'
        );
        $stmt->execute([$amount]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /** 标记订单已支付 */
    public static function markPaid(string $tradeNo): bool
    {
        $db = self::getInstance();
        $stmt = $db->prepare('UPDATE orders SET status = "paid", paid_at = NOW(), updated_at = NOW() WHERE trade_no = ? AND status = "created"');
        $stmt->execute([$tradeNo]);
        return $stmt->rowCount() > 0;
    }

    /** 标记过期订单 */
    public static function expireOrders(): int
    {
        $db = self::getInstance();
        $stmt = $db->exec('UPDATE orders SET status = "expired" WHERE status = "created" AND expires_at < NOW()');
        return $stmt;
    }

    public static function listOrders(int $limit = 100, int $offset = 0): array
    {
        $db = self::getInstance();
        $stmt = $db->prepare("SELECT * FROM orders ORDER BY id DESC LIMIT {$limit} OFFSET {$offset}");
        $stmt->execute();
        return $stmt->fetchAll();
    }

    public static function countOrders(): int
    {
        $db = self::getInstance();
        return (int) $db->query('SELECT COUNT(*) FROM orders')->fetchColumn();
    }

    public static function countPaidOrders(): int
    {
        $db = self::getInstance();
        return (int) $db->query('SELECT COUNT(*) FROM orders WHERE status = "paid"')->fetchColumn();
    }

    public static function sumPaidAmount(): float
    {
        $db = self::getInstance();
        return (float) $db->query('SELECT COALESCE(SUM(pay_amount), 0) FROM orders WHERE status = "paid"')->fetchColumn();
    }

    // ═══════════════════════════════════════════
    //  收款记录操作
    // ═══════════════════════════════════════════

    public static function addPayment(array $data): int
    {
        $db = self::getInstance();
        $stmt = $db->prepare(
            'INSERT INTO payments (amount, pay_type, raw_text, trade_no, matched, monitor_id, source, client_ip)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $data['amount'],
            $data['pay_type'] ?? 'wechat',
            $data['raw_text'] ?? '',
            $data['trade_no'] ?? '',
            $data['matched'] ?? 0,
            $data['monitor_id'] ?? '',
            $data['source'] ?? '',
            $data['client_ip'] ?? '',
        ]);
        return (int) $db->lastInsertId();
    }

    /** 检查最近时间窗口内是否已上报相同金额 (去重) */
    public static function isRecentPayment(float $amount, int $seconds = 30): bool
    {
        $db = self::getInstance();
        $stmt = $db->prepare(
            'SELECT COUNT(*) FROM payments WHERE amount = ? AND created_at > DATE_SUB(NOW(), INTERVAL ? SECOND)'
        );
        $stmt->execute([$amount, $seconds]);
        return (int) $stmt->fetchColumn() > 0;
    }

    public static function listPayments(int $limit = 100): array
    {
        $db = self::getInstance();
        return $db->query("SELECT * FROM payments ORDER BY id DESC LIMIT {$limit}")->fetchAll();
    }

    public static function countPayments(): int
    {
        $db = self::getInstance();
        return (int) $db->query('SELECT COUNT(*) FROM payments')->fetchColumn();
    }

    // ═══════════════════════════════════════════
    //  回调更新
    // ═══════════════════════════════════════════

    public static function updateNotifyStatus(string $tradeNo, string $status): void
    {
        $db = self::getInstance();
        $stmt = $db->prepare('UPDATE orders SET notify_status = ?, notify_count = notify_count + 1, updated_at = NOW() WHERE trade_no = ?');
        $stmt->execute([$status, $tradeNo]);
    }

    /** 获取需要回调的订单 (已支付但回调未成功) */
    public static function getPendingNotifyOrders(): array
    {
        $db = self::getInstance();
        return $db->query(
            'SELECT * FROM orders WHERE status = "paid" AND notify_status != "success" AND notify_count < ' . CALLBACK_RETRY . ' AND notify_url != ""'
        )->fetchAll();
    }
}
