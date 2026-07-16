<?php
/**
 * MaPay 码支付 - 管理后台
 * ======================
 * 订单管理、收款记录、统计面板
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

Database::initTables();
Database::expireOrders();

// 处理操作
if ($_POST['action'] ?? '') {
    if ($_POST['action'] === 'add_merchant') {
        $mid = $_POST['merchant_id'] ?? '';
        $name = $_POST['merchant_name'] ?? '';
        $key = bin2hex(random_bytes(16));
        $url = $_POST['callback_url'] ?? '';
        if ($mid && $name) {
            try {
                Database::addMerchant($mid, $name, $key, $url);
                $msg = "商户添加成功! ID: {$mid}, API_KEY: {$key}";
            } catch (Exception $e) {
                $msg = '添加失败: ' . $e->getMessage();
            }
        }
    }
}

$orders    = Database::listOrders(50);
$payments  = Database::listPayments(50);
$merchants = Database::listMerchants();

$stats = [
    'total_orders'   => Database::countOrders(),
    'paid_orders'    => Database::countPaidOrders(),
    'total_amount'   => Database::sumPaidAmount(),
    'total_payments' => Database::countPayments(),
];

$statusColors = [
    'created' => '#ff9c19',
    'paid'    => '#07c160',
    'expired' => '#999',
    'closed'  => '#fa5151',
];
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MaPay 码支付管理后台</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
               background: #f0f2f5; color: #333; }
        .header { background: linear-gradient(135deg, #07c160, #06ad56); color: #fff;
                  padding: 20px 24px; }
        .header h1 { font-size: 22px; font-weight: 600; }
        .header p { font-size: 13px; opacity: .9; margin-top: 4px; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }

        .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 20px; }
        .stat-card { background: #fff; border-radius: 10px; padding: 18px; box-shadow: 0 1px 4px rgba(0,0,0,.06); }
        .stat-card .label { font-size: 12px; color: #999; }
        .stat-card .value { font-size: 28px; font-weight: 700; margin-top: 6px; }
        .stat-card .value.green { color: #07c160; }
        .stat-card .value.orange { color: #ff9c19; }
        .stat-card .value.blue { color: #10aeff; }

        .card { background: #fff; border-radius: 10px; box-shadow: 0 1px 4px rgba(0,0,0,.06); margin-bottom: 20px; }
        .card-header { padding: 16px 20px; border-bottom: 1px solid #f0f0f0; display: flex; justify-content: space-between; align-items: center; }
        .card-header h2 { font-size: 16px; font-weight: 600; }
        .card-body { padding: 0; }

        table { width: 100%; border-collapse: collapse; }
        th { font-size: 12px; color: #999; text-align: left; padding: 10px 12px; border-bottom: 1px solid #f0f0f0; white-space: nowrap; }
        td { font-size: 13px; padding: 10px 12px; border-bottom: 1px solid #f5f5f5; }
        tr:hover { background: #fafafa; }

        .badge { display: inline-block; padding: 2px 10px; border-radius: 10px; font-size: 12px; font-weight: 500; }
        .badge-created { background: #fff5e6; color: #ff9c19; }
        .badge-paid { background: #e8f8ee; color: #07c160; }
        .badge-expired { background: #f5f5f5; color: #999; }
        .badge-closed { background: #ffe8e8; color: #fa5151; }
        .badge-yes { background: #e8f8ee; color: #07c160; }
        .badge-no { background: #f5f5f5; color: #999; }

        .msg { background: #e8f8ee; color: #07c160; padding: 12px 16px; border-radius: 8px; margin-bottom: 16px; font-size: 14px; }
        .msg code { background: #fff; padding: 2px 8px; border-radius: 4px; font-family: monospace; }

        .btn { padding: 6px 16px; border-radius: 6px; border: none; cursor: pointer; font-size: 13px; }
        .btn-green { background: #07c160; color: #fff; }
        .btn-green:hover { background: #06ad56; }

        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%;
                 background: rgba(0,0,0,.4); z-index: 999; }
        .modal.show { display: flex; align-items: center; justify-content: center; }
        .modal-content { background: #fff; border-radius: 12px; padding: 24px; width: 90%; max-width: 420px; }
        .modal-content h3 { margin-bottom: 16px; }
        .form-group { margin-bottom: 12px; }
        .form-group label { display: block; font-size: 13px; color: #666; margin-bottom: 4px; }
        .form-group input { width: 100%; padding: 8px 12px; border: 1px solid #ddd; border-radius: 6px; font-size: 14px; }

        .tabs { display: flex; gap: 0; }
        .tab { padding: 8px 20px; font-size: 14px; cursor: pointer; border-bottom: 2px solid transparent; }
        .tab.active { color: #07c160; border-bottom-color: #07c160; font-weight: 600; }
    </style>
</head>
<body>
    <div class="header">
        <h1>💚 MaPay 码支付管理后台</h1>
        <p>个人聚合支付系统 | 域名: <?= SITE_URL ?></p>
    </div>

    <div class="container">
        <?php if (!empty($msg)): ?>
        <div class="msg"><?= $msg ?></div>
        <?php endif; ?>

        <!-- 统计卡片 -->
        <div class="stats">
            <div class="stat-card">
                <div class="label">总订单数</div>
                <div class="value blue"><?= $stats['total_orders'] ?></div>
            </div>
            <div class="stat-card">
                <div class="label">已支付</div>
                <div class="value green"><?= $stats['paid_orders'] ?></div>
            </div>
            <div class="stat-card">
                <div class="label">支付总额</div>
                <div class="value green">¥<?= number_format($stats['total_amount'], 2) ?></div>
            </div>
            <div class="stat-card">
                <div class="label">收款记录</div>
                <div class="value orange"><?= $stats['total_payments'] ?></div>
            </div>
        </div>

        <!-- Tab切换 -->
        <div class="card">
            <div class="card-header">
                <div class="tabs">
                    <div class="tab active" onclick="switchTab('orders')">订单列表</div>
                    <div class="tab" onclick="switchTab('payments')">收款记录</div>
                    <div class="tab" onclick="switchTab('merchants')">商户管理</div>
                </div>
                <button class="btn btn-green" onclick="showModal()">+ 添加商户</button>
            </div>
            <div class="card-body">
                <!-- 订单列表 -->
                <div id="tab-orders">
                    <table>
                        <thead>
                            <tr>
                                <th>系统订单号</th>
                                <th>商户订单号</th>
                                <th>商户ID</th>
                                <th>请求金额</th>
                                <th>实付金额</th>
                                <th>状态</th>
                                <th>回调</th>
                                <th>创建时间</th>
                                <th>支付时间</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($orders as $o): ?>
                            <tr>
                                <td style="font-family:monospace;font-size:12px;"><?= substr($o['trade_no'], 0, 20) ?>...</td>
                                <td style="font-size:12px;"><?= htmlspecialchars($o['out_trade_no']) ?></td>
                                <td><?= htmlspecialchars($o['merchant_id']) ?></td>
                                <td>¥<?= $o['amount'] ?></td>
                                <td style="font-weight:600;color:#07c160;">¥<?= $o['pay_amount'] ?></td>
                                <td><span class="badge badge-<?= $o['status'] ?>"><?= $o['status'] ?></span></td>
                                <td><span class="badge badge-<?= $o['notify_status'] === 'success' ? 'yes' : 'no' ?>"><?= $o['notify_status'] ?></span></td>
                                <td style="font-size:12px;"><?= $o['created_at'] ?></td>
                                <td style="font-size:12px;"><?= $o['paid_at'] ?: '-' ?></td>
                            </tr>
                            <?php endforeach; ?>
                            <?php if (empty($orders)): ?>
                            <tr><td colspan="9" style="text-align:center;padding:40px;color:#999;">暂无订单</td></tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>

                <!-- 收款记录 -->
                <div id="tab-payments" style="display:none;">
                    <table>
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>金额</th>
                                <th>支付方式</th>
                                <th>匹配</th>
                                <th>订单号</th>
                                <th>监控端</th>
                                <th>来源</th>
                                <th>时间</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($payments as $p): ?>
                            <tr>
                                <td><?= $p['id'] ?></td>
                                <td style="font-weight:600;color:#07c160;">¥<?= $p['amount'] ?></td>
                                <td><?= $p['pay_type'] ?></td>
                                <td><span class="badge badge-<?= $p['matched'] ? 'yes' : 'no' ?>"><?= $p['matched'] ? '已匹配' : '未匹配' ?></span></td>
                                <td style="font-size:12px;"><?= $p['trade_no'] ?: '-' ?></td>
                                <td><?= htmlspecialchars($p['monitor_id']) ?></td>
                                <td><?= htmlspecialchars($p['source']) ?></td>
                                <td style="font-size:12px;"><?= $p['created_at'] ?></td>
                            </tr>
                            <?php endforeach; ?>
                            <?php if (empty($payments)): ?>
                            <tr><td colspan="8" style="text-align:center;padding:40px;color:#999;">暂无收款记录</td></tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>

                <!-- 商户管理 -->
                <div id="tab-merchants" style="display:none;">
                    <table>
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>商户号</th>
                                <th>名称</th>
                                <th>API Key</th>
                                <th>回调URL</th>
                                <th>状态</th>
                                <th>创建时间</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($merchants as $m): ?>
                            <tr>
                                <td><?= $m['id'] ?></td>
                                <td style="font-weight:600;"><?= htmlspecialchars($m['merchant_id']) ?></td>
                                <td><?= htmlspecialchars($m['merchant_name']) ?></td>
                                <td style="font-family:monospace;font-size:12px;"><?= substr($m['api_key'], 0, 16) ?>...</td>
                                <td style="font-size:12px;max-width:200px;overflow:hidden;text-overflow:ellipsis;"><?= htmlspecialchars($m['callback_url']) ?></td>
                                <td><span class="badge badge-<?= $m['status'] ? 'yes' : 'no' ?>"><?= $m['status'] ? '启用' : '禁用' ?></span></td>
                                <td style="font-size:12px;"><?= $m['created_at'] ?></td>
                            </tr>
                            <?php endforeach; ?>
                            <?php if (empty($merchants)): ?>
                            <tr><td colspan="7" style="text-align:center;padding:40px;color:#999;">暂无商户，请添加商户</td></tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- 添加商户弹窗 -->
    <div class="modal" id="merchantModal">
        <div class="modal-content">
            <h3>添加商户</h3>
            <form method="POST">
                <input type="hidden" name="action" value="add_merchant">
                <div class="form-group">
                    <label>商户号 (merchant_id)</label>
                    <input type="text" name="merchant_id" placeholder="如: M100001" required>
                </div>
                <div class="form-group">
                    <label>商户名称</label>
                    <input type="text" name="merchant_name" placeholder="如: 测试商户" required>
                </div>
                <div class="form-group">
                    <label>回调URL (可选)</label>
                    <input type="text" name="callback_url" placeholder="https://your-site.com/callback">
                </div>
                <p style="font-size:12px;color:#999;margin-bottom:12px;">API Key 将自动生成</p>
                <button type="submit" class="btn btn-green" style="width:100%;padding:10px;">添加</button>
            </form>
        </div>
    </div>

    <script>
        function switchTab(name) {
            document.querySelectorAll('[id^="tab-"]').forEach(el => el.style.display = 'none');
            document.getElementById('tab-' + name).style.display = '';
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            event.target.classList.add('active');
        }
        function showModal() {
            document.getElementById('merchantModal').classList.add('show');
        }
        document.getElementById('merchantModal').addEventListener('click', function(e) {
            if (e.target === this) this.classList.remove('show');
        });
    </script>
</body>
</html>
