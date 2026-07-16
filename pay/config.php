<?php
/**
 * MaPay 码支付 - 配置文件
 * ========================
 * 所有配置项集中管理
 */

// ── 数据库配置 (MySQL) ──────────────────────────────
define('DB_HOST', '127.0.0.1');
define('DB_PORT', 3306);
define('DB_NAME', 'mapay');
define('DB_USER', 'root');
define('DB_PASS', '');  // skip-grant-tables 模式，无密码

// ── 系统配置 ────────────────────────────────────────
define('SITE_NAME',   'MaPay 码支付');
define('SITE_URL',    'http://pay.yzfaiu.xyz');
define('TIMEZONE',    'Asia/Shanghai');
define('DEBUG',       false);

// ── 订单配置 ────────────────────────────────────────
define('ORDER_EXPIRE_SECONDS', 300);     // 订单过期时间 5分钟
define('AMOUNT_RANDOM_MIN',    0.01);    // 金额随机最小值
define('AMOUNT_RANDOM_MAX',    0.99);    // 金额随机最大值
define('MONITOR_DEDUP_SECONDS', 30);     // 监控端去重时间窗口

// ── 回调配置 ────────────────────────────────────────
define('CALLBACK_TIMEOUT',  10);   // 回调超时秒数
define('CALLBACK_RETRY',    5);    // 回调重试次数

// ── 收款码图片 ──────────────────────────────────────
// 把你的微信收款码图片放到 data/ 目录，命名为 wechat_qr.png
define('QR_IMAGE_PATH', __DIR__ . '/data/wechat_qr.png');
define('QR_IMAGE_DEFAULT', __DIR__ . '/data/default_qr.png');

// ── 时区 ────────────────────────────────────────────
date_default_timezone_set(TIMEZONE);

// ── 错误报告 ────────────────────────────────────────
if (DEBUG) {
    error_reporting(E_ALL);
    ini_set('display_errors', 1);
} else {
    error_reporting(0);
    ini_set('display_errors', 0);
}

// ── 工具函数 ────────────────────────────────────────

/**
 * 生成MD5签名
 * 规则: 参数按key排序拼接 → 末尾追加key → MD5 → 转大写
 */
function generateSign(array $params, string $secretKey): string {
    $filtered = [];
    foreach ($params as $k => $v) {
        if ($v !== '' && $v !== null && $k !== 'sign' && $k !== 'action') {
            $filtered[$k] = $v;
        }
    }
    ksort($filtered);
    $parts = [];
    foreach ($filtered as $k => $v) {
        $parts[] = "{$k}={$v}";
    }
    $str = implode('&', $parts) . "&key={$secretKey}";
    return strtoupper(md5($str));
}

/** 验证签名 */
function verifySign(array $params, string $secretKey): bool {
    if (!isset($params['sign'])) return false;
    $expected = generateSign($params, $secretKey);
    return hash_equals($expected, $params['sign']);
}

/** JSON响应 */
function jsonResponse(int $code, string $msg = '', array $data = []): void {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(array_merge(['code' => $code, 'msg' => $msg], $data), JSON_UNESCAPED_UNICODE);
    exit;
}

/** 生成订单号 */
function generateTradeNo(): string {
    return 'M' . date('YmdHis') . strtoupper(substr(md5(uniqid(mt_rand(), true)), 0, 6));
}

/** 金额随机化 (防重) - 已禁用，实付金额=请求金额 */
function randomizeAmount(float $amount): float {
    return round($amount, 2);
}

/** 获取客户端IP */
function getClientIp(): string {
    $keys = ['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'REMOTE_ADDR'];
    foreach ($keys as $k) {
        if (!empty($_SERVER[$k])) {
            $ip = trim(explode(',', $_SERVER[$k])[0]);
            if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
        }
    }
    return '0.0.0.0';
}

/** 日志记录 */
function writeLog(string $message, string $level = 'INFO'): void {
    $logFile = __DIR__ . '/data/app.log';
    $time = date('Y-m-d H:i:s');
    $line = "[{$time}] [{$level}] {$message}\n";
    @file_put_contents($logFile, $line, FILE_APPEND);
}
