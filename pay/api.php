<?php
/**
 * MaPay 码支付 - API入口
 * ======================
 * 统一API路由，支持以下接口:
 *
 * 商户API (需要MD5签名):
 *   POST /api.php?action=order_create   创建订单
 *   POST /api.php?action=order_query    查询订单
 *   GET  /api.php?action=health         健康检查
 *
 * 监控端API (需要MD5签名):
 *   POST /api.php?action=monitor_report 监控端上报收款
 *
 * 管理API:
 *   GET  /api.php?action=stats          统计数据
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

// 初始化数据库表
Database::initTables();

// 过期订单清理
Database::expireOrders();

// 路由
$action = $_GET['action'] ?? $_POST['action'] ?? '';

try {
    switch ($action) {
        case 'order_create':
            handleOrderCreate();
            break;
        case 'order_query':
            handleOrderQuery();
            break;
        case 'order_close':
            handleOrderClose();
            break;
        case 'monitor_report':
            handleMonitorReport();
            break;
        case 'monitor_upload_logs':
            handleMonitorUploadLogs();
            break;
        case 'monitor_view_logs':
            handleMonitorViewLogs();
            break;
        case 'health':
            handleHealth();
            break;
        case 'stats':
            handleStats();
            break;
        default:
            jsonResponse(404, 'Unknown action');
    }
} catch (Throwable $e) {
    writeLog('API异常: ' . $e->getMessage(), 'ERROR');
    jsonResponse(500, 'Server error');
}

// ═══════════════════════════════════════════════════════
//  处理函数
// ═══════════════════════════════════════════════════════

/**
 * 创建订单
 * 必填: merchant_id, out_trade_no, amount, sign
 * 可选: title, attach, notify_url, pay_type
 */
function handleOrderCreate(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonResponse(405, 'POST only');
    }

    $params = array_merge($_POST, $_GET);

    // 参数校验
    $required = ['merchant_id', 'out_trade_no', 'amount', 'sign'];
    foreach ($required as $field) {
        if (!isset($params[$field]) || $params[$field] === '') {
            jsonResponse(400, "Missing param: {$field}");
        }
    }

    $merchantId = $params['merchant_id'];
    $outTradeNo = $params['out_trade_no'];
    $amount     = (float) $params['amount'];

    if ($amount <= 0 || $amount > 100000) {
        jsonResponse(400, 'Invalid amount (0 < amount <= 100000)');
    }

    // 查商户
    $merchant = Database::getMerchant($merchantId);
    if (!$merchant) {
        jsonResponse(401, 'Merchant not found or disabled');
    }

    // 验签
    if (!verifySign($params, $merchant['api_key'])) {
        writeLog("签名验证失败: merchant={$merchantId}, out_trade_no={$outTradeNo}", 'WARN');
        jsonResponse(401, 'Sign verification failed');
    }

    // 检查重复订单
    $existing = Database::getOrderByMerchantNo($merchantId, $outTradeNo);
    if ($existing) {
        // 已有订单，返回已有信息
        jsonResponse(200, 'Order already exists', [
            'trade_no'    => $existing['trade_no'],
            'out_trade_no'=> $existing['out_trade_no'],
            'amount'      => $existing['amount'],
            'pay_amount'  => $existing['pay_amount'],
            'status'      => $existing['status'],
            'pay_url'     => SITE_URL . '/pay.php?trade_no=' . $existing['trade_no'],
        ]);
    }

    // 金额随机化
    $payAmount = randomizeAmount($amount);

    // 生成订单
    $tradeNo   = generateTradeNo();
    $expiresAt = date('Y-m-d H:i:s', time() + ORDER_EXPIRE_SECONDS);

    $order = Database::createOrder([
        'trade_no'     => $tradeNo,
        'merchant_id'  => $merchantId,
        'out_trade_no' => $outTradeNo,
        'amount'       => $amount,
        'pay_amount'   => $payAmount,
        'title'        => $params['title'] ?? '商品支付',
        'attach'       => $params['attach'] ?? '',
        'pay_type'     => $params['pay_type'] ?? 'wechat',
        'client_ip'    => getClientIp(),
        'notify_url'   => $params['notify_url'] ?? $merchant['callback_url'],
        'expires_at'   => $expiresAt,
    ]);

    writeLog("订单创建: trade_no={$tradeNo}, merchant={$merchantId}, amount={$amount}, pay_amount={$payAmount}");

    jsonResponse(200, 'success', [
        'trade_no'     => $tradeNo,
        'out_trade_no' => $outTradeNo,
        'amount'       => number_format($amount, 2, '.', ''),
        'pay_amount'   => number_format($payAmount, 2, '.', ''),
        'status'       => 'created',
        'pay_url'      => SITE_URL . '/pay.php?trade_no=' . $tradeNo,
        'expires_at'   => $expiresAt,
    ]);
}

/**
 * 查询订单
 * 必填: merchant_id, trade_no (或 out_trade_no), sign
 */
function handleOrderQuery(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonResponse(405, 'POST only');
    }

    $params = array_merge($_POST, $_GET);

    $required = ['merchant_id', 'sign'];
    foreach ($required as $field) {
        if (!isset($params[$field]) || $params[$field] === '') {
            jsonResponse(400, "Missing param: {$field}");
        }
    }

    $merchantId = $params['merchant_id'];
    $merchant = Database::getMerchant($merchantId);
    if (!$merchant) {
        jsonResponse(401, 'Merchant not found');
    }

    if (!verifySign($params, $merchant['api_key'])) {
        jsonResponse(401, 'Sign verification failed');
    }

    // 查找订单
    $order = null;
    if (!empty($params['trade_no'])) {
        $order = Database::getOrder($params['trade_no']);
    } elseif (!empty($params['out_trade_no'])) {
        $order = Database::getOrderByMerchantNo($merchantId, $params['out_trade_no']);
    }

    if (!$order) {
        jsonResponse(404, 'Order not found');
    }

    if ($order['merchant_id'] !== $merchantId) {
        jsonResponse(403, 'Order does not belong to this merchant');
    }

    jsonResponse(200, 'success', [
        'trade_no'       => $order['trade_no'],
        'out_trade_no'   => $order['out_trade_no'],
        'amount'         => $order['amount'],
        'pay_amount'     => $order['pay_amount'],
        'status'         => $order['status'],
        'pay_type'       => $order['pay_type'],
        'paid_at'        => $order['paid_at'] ?? '',
        'created_at'     => $order['created_at'],
        'expires_at'     => $order['expires_at'],
        'notify_status'  => $order['notify_status'],
    ]);
}

/**
 * 监控端上报收款
 * 接收JSON: {amount, pay_type, raw_text, timestamp, monitor, source, sign}
 */
function handleMonitorReport(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonResponse(405, 'POST only');
    }

    // 接收JSON或表单
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    if (!$data) {
        $data = $_POST;
    }

    if (empty($data['amount'])) {
        jsonResponse(400, 'Missing amount');
    }

    $amount = (float) $data['amount'];

    // 验签 - 使用商户的api_key作为监控密钥的替代
    // 实际上监控端使用固定密钥验证
    $monitorSecret = $data['monitor_secret'] ?? '';
    // 支持两种验证方式: 1. monitor_secret字段 2. sign签名
    if (!empty($monitorSecret)) {
        // 简单密钥验证模式
        $expectedSecret = getenv('MAPAY_MONITOR_SECRET') ?: 'mapay_monitor_2024';
        if ($monitorSecret !== $expectedSecret) {
            jsonResponse(401, 'Invalid monitor secret');
        }
    } elseif (!empty($data['sign'])) {
        // 签名验证模式
        $signKey = getenv('MAPAY_MONITOR_SECRET') ?: 'mapay_monitor_2024';
        if (!verifySign($data, $signKey)) {
            jsonResponse(401, 'Sign verification failed');
        }
    } else {
        jsonResponse(401, 'Authentication required (monitor_secret or sign)');
    }

    // 去重检查
    if (Database::isRecentPayment($amount, MONITOR_DEDUP_SECONDS)) {
        writeLog("监控端重复上报(去重): amount={$amount}", 'WARN');
        jsonResponse(200, 'Duplicate (deduplicated)', ['matched' => false]);
    }

    // 匹配订单
    $order = Database::findPendingByAmount($amount);
    $matched = false;
    $tradeNo = '';

    $monitorId = $data['monitor'] ?? 'unknown';

    if ($order) {
        Database::markPaid($order['trade_no']);
        $matched = true;
        $tradeNo = $order['trade_no'];
        writeLog("支付匹配成功: trade_no={$tradeNo}, amount={$amount}, monitor={$monitorId}");

        // 异步触发回调
        sendNotifyCallback($order['trade_no']);
    } else {
        writeLog("支付未匹配到订单: amount={$amount}, monitor={$monitorId}", 'WARN');
    }

    // 记录收款
    Database::addPayment([
        'amount'     => $amount,
        'pay_type'   => $data['pay_type'] ?? 'wechat',
        'raw_text'   => $data['raw_text'] ?? '',
        'trade_no'   => $tradeNo,
        'matched'    => $matched ? 1 : 0,
        'monitor_id' => $data['monitor'] ?? '',
        'source'     => $data['source'] ?? '',
        'client_ip'  => getClientIp(),
    ]);

    jsonResponse(200, 'success', [
        'matched'   => $matched,
        'trade_no'  => $tradeNo,
        'amount'    => number_format($amount, 2, '.', ''),
    ]);
}

/**
 * 健康检查
 */
function handleHealth(): void
{
    jsonResponse(200, 'ok', [
        'service'  => 'MaPay',
        'version'  => '1.0',
        'time'     => date('Y-m-d H:i:s'),
        'php'      => PHP_VERSION,
        'db'       => 'mysql',
    ]);
}

/**
 * 统计数据
 */
function handleStats(): void
{
    $stats = [
        'total_orders'   => Database::countOrders(),
        'paid_orders'    => Database::countPaidOrders(),
        'total_amount'   => number_format(Database::sumPaidAmount(), 2, '.', ''),
        'total_payments' => Database::countPayments(),
    ];
    jsonResponse(200, 'success', $stats);
}

// ═══════════════════════════════════════════════════════

/**
 * 关闭订单 (商户主动关闭未支付订单)
 * 必填: merchant_id, trade_no, sign
 */
function handleOrderClose(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonResponse(405, 'POST only');
    }

    $params = array_merge($_POST, $_GET);

    $required = ['merchant_id', 'trade_no', 'sign'];
    foreach ($required as $field) {
        if (!isset($params[$field]) || $params[$field] === '') {
            jsonResponse(400, "Missing param: {$field}");
        }
    }

    $merchantId = $params['merchant_id'];
    $merchant = Database::getMerchant($merchantId);
    if (!$merchant) {
        jsonResponse(401, 'Merchant not found');
    }

    if (!verifySign($params, $merchant['api_key'])) {
        jsonResponse(401, 'Sign verification failed');
    }

    $order = Database::getOrder($params['trade_no']);
    if (!$order) {
        jsonResponse(404, 'Order not found');
    }

    if ($order['merchant_id'] !== $merchantId) {
        jsonResponse(403, 'Order does not belong to this merchant');
    }

    // 只有 created 状态的订单可以关闭
    if ($order['status'] !== 'created') {
        jsonResponse(400, 'Order cannot be closed (current status: ' . $order['status'] . ')');
    }

    $db = Database::getInstance();
    $stmt = $db->prepare('UPDATE orders SET status = "closed", updated_at = NOW() WHERE trade_no = ? AND status = "created"');
    $stmt->execute([$params['trade_no']]);

    writeLog("订单关闭: trade_no={$params['trade_no']}, merchant={$merchantId}");
    jsonResponse(200, 'success', [
        'trade_no' => $params['trade_no'],
        'status'   => 'closed',
    ]);
}

//  监控端日志上传
// ═══════════════════════════════════════════════════════

/**
 * 接收监控端(iOS/PC)上传的日志
 * POST /api.php?action=monitor_upload_logs
 */
function handleMonitorUploadLogs(): void
{
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        jsonResponse(405, 'POST only');
    }

    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    if (!$data) {
        $data = $_POST;
    }

    $monitorSecret = $data['monitor_secret'] ?? '';
    $expectedSecret = getenv('MAPAY_MONITOR_SECRET') ?: 'mapay_monitor_2024';
    if ($monitorSecret !== $expectedSecret) {
        jsonResponse(401, 'Invalid monitor secret');
    }

    $monitorId = $data['monitor'] ?? 'unknown';
    $logs = $data['logs'] ?? [];
    $clientIp = $_SERVER['REMOTE_ADDR'] ?? '';

    if (empty($logs) || !is_array($logs)) {
        jsonResponse(400, 'No logs provided');
    }

    $db = Database::getInstance();
    $inserted = 0;

    foreach ($logs as $log) {
        $ts = $log['ts'] ?? time();
        $level = $log['level'] ?? 'INFO';
        $msg = $log['msg'] ?? '';
        $event = strtoupper($level);

        if (strlen($msg) > 60000) {
            $msg = substr($msg, 0, 60000);
        }

        $detail = date('Y-m-d H:i:s', $ts) . ' [' . $level . '] ' . $msg;

        try {
            $stmt = $db->prepare('INSERT INTO monitor_logs (monitor_id, event, detail, client_ip) VALUES (?, ?, ?, ?)');
            $stmt->execute([$monitorId, $event, $detail, $clientIp]);
            $inserted++;
        } catch (Exception $e) {
            writeLog('日志插入失败: ' . $e->getMessage(), 'ERROR');
        }
    }

    writeLog("日志上传: monitor={$monitorId}, count={$inserted}");

    jsonResponse(200, 'success', [
        'received' => count($logs),
        'inserted' => $inserted,
        'monitor'  => $monitorId,
    ]);
}

/**
 * 查看监控端日志 (API)
 * GET /api.php?action=monitor_view_logs&monitor=xxx&limit=50&secret=xxx
 */
function handleMonitorViewLogs(): void
{
    $secret = $_GET['secret'] ?? $_POST['secret'] ?? '';
    $expectedSecret = getenv('MAPAY_MONITOR_SECRET') ?: 'mapay_monitor_2024';
    if ($secret !== $expectedSecret) {
        jsonResponse(401, 'Invalid monitor secret');
    }

    $monitor = $_GET['monitor'] ?? '';
    $limit = min((int)($_GET['limit'] ?? 100), 500);

    $db = Database::getInstance();

    if ($monitor) {
        $stmt = $db->prepare('SELECT * FROM monitor_logs WHERE monitor_id = ? ORDER BY id DESC LIMIT ?');
        $stmt->execute([$monitor, $limit]);
    } else {
        $stmt = $db->prepare('SELECT * FROM monitor_logs ORDER BY id DESC LIMIT ?');
        $stmt->execute([$limit]);
    }

    $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

    jsonResponse(200, 'success', [
        'count' => count($logs),
        'logs'  => $logs,
    ]);
}

//  回调通知
// ═══════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════

/**
 * 发送回调通知到商户
 */
function sendNotifyCallback(string $tradeNo): void
{
    $order = Database::getOrder($tradeNo);
    if (!$order || empty($order['notify_url'])) {
        return;
    }

    $merchant = Database::getMerchant($order['merchant_id']);
    if (!$merchant) return;

    // 构造回调数据
    $notifyData = [
        'trade_no'      => $order['trade_no'],
        'out_trade_no'  => $order['out_trade_no'],
        'merchant_id'   => $order['merchant_id'],
        'amount'        => $order['amount'],
        'pay_amount'    => $order['pay_amount'],
        'status'        => 'paid',
        'paid_at'       => $order['paid_at'],
        'timestamp'     => time(),
    ];
    $notifyData['sign'] = generateSign($notifyData, $merchant['api_key']);

    // 发送HTTP POST
    $ch = curl_init($order['notify_url']);
    curl_setopt_array($ch, [
        CURLOPT_POST       => true,
        CURLOPT_POSTFIELDS => http_build_query($notifyData),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT    => CALLBACK_TIMEOUT,
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
    ]);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error    = curl_error($ch);
    curl_close($ch);

    // 商户返回 "success" 视为成功
    if ($httpCode === 200 && trim($response) === 'success') {
        Database::updateNotifyStatus($tradeNo, 'success');
        writeLog("回调成功: trade_no={$tradeNo}, url={$order['notify_url']}");
    } else {
        Database::updateNotifyStatus($tradeNo, 'failed');
        writeLog("回调失败: trade_no={$tradeNo}, http={$httpCode}, resp={$response}, err={$error}", 'WARN');
    }
}
