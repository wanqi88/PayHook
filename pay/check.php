<?php
/**
 * MaPay 码支付 - 订单状态查询接口
 * ================================
 * JSONP方式返回订单状态，供支付页面轮询
 * 访问: /check.php?trade_no=Mxxxxxxxx&cb=callback
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

Database::initTables();
Database::expireOrders();

$tradeNo = $_GET['trade_no'] ?? '';
$callback = $_GET['cb'] ?? 'onCheck';

if (!$tradeNo) {
    header('Content-Type: application/javascript');
    echo $callback . '(' . json_encode(['error' => 'missing trade_no']) . ');';
    exit;
}

$order = Database::getOrder($tradeNo);

$data = [
    'trade_no' => $tradeNo,
    'status'   => $order ? $order['status'] : 'not_found',
];

if ($order) {
    $data['pay_amount'] = $order['pay_amount'];
    $data['paid_at']    = $order['paid_at'];
}

header('Content-Type: application/javascript; charset=utf-8');
echo $callback . '(' . json_encode($data, JSON_UNESCAPED_UNICODE) . ');';
