<?php
/**
 * MaPay 码支付 - 支付页面
 * =======================
 * 展示收款码+金额，自动轮询订单状态
 * 访问: /pay.php?trade_no=Mxxxxxxxx
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

Database::initTables();
Database::expireOrders();

$tradeNo = $_GET['trade_no'] ?? '';
if (!$tradeNo) {
    http_response_code(400);
    echo 'Missing trade_no';
    exit;
}

$order = Database::getOrder($tradeNo);
if (!$order) {
    http_response_code(404);
    echo 'Order not found';
    exit;
}

// 检查是否过期
$isExpired = ($order['status'] === 'expired') || ($order['expires_at'] && strtotime($order['expires_at']) < time());
$isPaid = ($order['status'] === 'paid');

// QR码图片URL (支持data URI或文件)
$qrSrc = '';
if (file_exists(QR_IMAGE_PATH)) {
    $qrSrc = 'data:image/png;base64,' . base64_encode(file_get_contents(QR_IMAGE_PATH));
} elseif (file_exists(QR_IMAGE_DEFAULT)) {
    $qrSrc = 'data:image/png;base64,' . base64_encode(file_get_contents(QR_IMAGE_DEFAULT));
} else {
    // 生成占位二维码
    $qrSrc = SITE_URL . '/qrcode.php?text=' . urlencode('https://example.com');
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>微信支付 - ¥<?=$order['pay_amount']?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
            background: #f5f5f5; color: #333; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
        }
        .pay-card {
            background: #fff; border-radius: 16px; padding: 32px 24px;
            width: 100%; max-width: 360px; text-align: center;
            box-shadow: 0 2px 16px rgba(0,0,0,.08);
        }
        .pay-header { margin-bottom: 20px; }
        .pay-header .logo { font-size: 28px; }
        .pay-header .title { font-size: 16px; color: #07c160; font-weight: 600; margin-top: 8px; }

        .amount-box { margin: 20px 0; }
        .amount-box .label { font-size: 13px; color: #999; }
        .amount-box .amount { font-size: 42px; font-weight: 700; color: #07c160; margin: 8px 0; }
        .amount-box .amount .unit { font-size: 20px; }
        .amount-box .hint { font-size: 12px; color: #fa5151; background: #fff5f5; padding: 6px 12px; border-radius: 6px; display: inline-block; }

        .qr-box { margin: 20px 0; }
        .qr-box img { width: 220px; height: 220px; border-radius: 8px; border: 1px solid #eee; }
        .qr-box .tip { font-size: 13px; color: #666; margin-top: 12px; }

        .status-box { margin: 20px 0; }
        .status-box .status-text { font-size: 16px; font-weight: 600; }
        .status-box .status-text.waiting { color: #ff9c19; }
        .status-box .status-text.paid { color: #07c160; }
        .status-box .status-text.expired { color: #999; }

        .spinner {
            width: 20px; height: 20px; border: 2px solid #eee;
            border-top-color: #07c160; border-radius: 50%;
            animation: spin .8s linear infinite; margin: 0 auto 8px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        .info { font-size: 12px; color: #999; margin-top: 16px; padding-top: 16px; border-top: 1px solid #f0f0f0; }
        .info div { margin: 4px 0; }
        .info .trade-no { font-family: monospace; }

        .btn { display: block; width: 100%; padding: 12px; border-radius: 8px; font-size: 15px;
               border: none; cursor: pointer; margin-top: 12px; }
        .btn-refresh { background: #f5f5f5; color: #666; }

        .success-icon { font-size: 48px; margin-bottom: 8px; }
    </style>
</head>
<body>
    <div class="pay-card">
        <div class="pay-header">
            <div class="logo">💚</div>
            <div class="title">微信支付</div>
        </div>

        <?php if ($isPaid): ?>
            <!-- 支付成功 -->
            <div class="status-box">
                <div class="success-icon">✅</div>
                <div class="status-text paid">支付成功</div>
            </div>
            <div class="amount-box">
                <div class="amount"><span class="unit">¥</span><?= htmlspecialchars($order['pay_amount']) ?></div>
            </div>

        <?php elseif ($isExpired): ?>
            <!-- 已过期 -->
            <div class="status-box">
                <div class="status-text expired">⏰ 订单已过期</div>
                <div style="font-size:13px;color:#999;margin-top:8px;">请重新发起支付</div>
            </div>

        <?php else: ?>
            <!-- 等待支付 -->
            <div class="amount-box">
                <div class="label">需支付</div>
                <div class="amount"><span class="unit">¥</span><?= htmlspecialchars($order['pay_amount']) ?></div>
                <div class="hint">⚠ 请扫描下方二维码，支付精确金额</div>
            </div>

            <div class="qr-box">
                <img src="<?= $qrSrc ?>" alt="收款码">
                <div class="tip">打开微信扫一扫</div>
            </div>

            <div class="status-box">
                <div class="spinner"></div>
                <div class="status-text waiting" id="statusText">等待买家付款...</div>
            </div>
        <?php endif; ?>

        <div class="info">
            <div>订单号: <span class="trade-no"><?= htmlspecialchars($order['trade_no']) ?></span></div>
            <div>商户订单: <?= htmlspecialchars($order['out_trade_no']) ?></div>
            <?php if ($order['title']): ?>
            <div>商品: <?= htmlspecialchars($order['title']) ?></div>
            <?php endif; ?>
            <div>创建时间: <?= htmlspecialchars($order['created_at']) ?></div>
            <?php if ($order['paid_at']): ?>
            <div>支付时间: <?= htmlspecialchars($order['paid_at']) ?></div>
            <?php endif; ?>
        </div>
    </div>

    <?php if (!$isPaid && !$isExpired): ?>
    <script>
        const tradeNo = '<?= $order['trade_no'] ?>';
        let pollCount = 0;
        const maxPolls = 100; // 最多轮询100次 (5分钟)

        function poll() {
            if (pollCount >= maxPolls) {
                location.reload();
                return;
            }
            pollCount++;

            fetch('api.php?action=health', { cache: 'no-store' })
                .then(() => {
                    // 用JSONP替代fetch避免CORS
                    const script = document.createElement('script');
                    script.src = 'check.php?trade_no=' + tradeNo + '&cb=onCheck';
                    document.body.appendChild(script);
                })
                .catch(() => {
                    setTimeout(poll, 3000);
                });
        }

        function onCheck(data) {
            if (data && data.status === 'paid') {
                location.reload();
            } else if (data && data.status === 'expired') {
                location.reload();
            } else {
                setTimeout(poll, 3000);
            }
        }

        setTimeout(poll, 3000);
    </script>
    <?php endif; ?>
</body>
</html>
