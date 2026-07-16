<?php
/**
 * MaPay 码支付 - 回调通知接收器 (Demo)
 * =====================================
 * 这个文件是给商户的回调接收示例
 * 商户需要在自己的服务器上部署类似的脚本来接收支付通知
 *
 * 回调数据格式 (POST application/x-www-form-urlencoded):
 *   trade_no      系统订单号
 *   out_trade_no  商户订单号
 *   merchant_id   商户号
 *   amount        请求金额
 *   pay_amount    实付金额
 *   status        状态 (paid)
 *   paid_at       支付时间
 *   timestamp     时间戳
 *   sign          MD5签名
 */

// 接收回调数据
$data = $_POST;

// 验证签名 (商户需要用自己的API_KEY验签)
// $apiKey = 'your_api_key';
// $expectedSign = generateSign($data, $apiKey);
// if ($data['sign'] !== $expectedSign) {
//     echo 'sign error';
//     exit;
// }

// 记录日志
$log = date('Y-m-d H:i:s') . ' ' . json_encode($data, JSON_UNESCAPED_UNICODE) . "\n";
@file_put_contents(__DIR__ . '/data/callback.log', $log, FILE_APPEND);

// 商户业务逻辑: 更新订单状态、发货等
// ...

// 返回 "success" 告知服务端回调成功
echo 'success';
