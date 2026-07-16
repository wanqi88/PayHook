<?php
/**
 * MaPay 码支付 - 初始化脚本
 * ==========================
 * 命令行运行: php init.php
 * 功能: 建表 → 添加默认商户 → 检查环境
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';

echo "╔══════════════════════════════════════════╗\n";
echo "║  MaPay 码支付 - 服务端初始化              ║\n";
echo "╚══════════════════════════════════════════╝\n\n";

// 1. 检查PHP环境
echo "[1] 检查PHP环境...\n";
$exts = ['pdo', 'pdo_mysql', 'curl', 'json', 'mbstring', 'gd'];
$missing = [];
foreach ($exts as $ext) {
    if (extension_loaded($ext)) {
        echo "  ✅ {$ext}\n";
    } else {
        echo "  ❌ {$ext} (缺失)\n";
        $missing[] = $ext;
    }
}
echo "  PHP版本: " . PHP_VERSION . "\n\n";

if (!empty($missing)) {
    echo "⚠ 缺少扩展，请安装: apt-get install php-" . implode(' php-', $missing) . "\n\n";
}

// 2. 初始化数据库
echo "[2] 初始化数据库 (MySQL)...\n";
try {
    Database::initTables();
    echo "  ✅ 表创建成功\n";

    $db = Database::getInstance();
    $tables = $db->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
    echo "  数据表: " . implode(', ', $tables) . "\n\n";
} catch (Exception $e) {
    echo "  ❌ 数据库初始化失败: " . $e->getMessage() . "\n";
    echo "  请检查 config.php 中的数据库配置\n\n";
    exit(1);
}

// 3. 添加默认商户
echo "[3] 添加默认商户...\n";
$existing = Database::getMerchant('M100001');
if ($existing) {
    echo "  ✅ 默认商户已存在: M100001\n";
    echo "     API Key: " . $existing['api_key'] . "\n\n";
} else {
    $apiKey = 'test_api_key_' . bin2hex(random_bytes(8));
    Database::addMerchant('M100001', '测试商户', $apiKey, '');
    echo "  ✅ 默认商户已创建\n";
    echo "     商户号: M100001\n";
    echo "     API Key: {$apiKey}\n\n";
}

// 4. 创建数据目录
echo "[4] 创建数据目录...\n";
$dirs = [
    __DIR__ . '/data',
    __DIR__ . '/data/screenshots',
];
foreach ($dirs as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
        echo "  ✅ 创建: {$dir}\n";
    } else {
        echo "  ✅ 已有: {$dir}\n";
    }
}
echo "\n";

// 5. 打印配置信息
echo "[5] 配置信息...\n";
echo "  站点URL: " . SITE_URL . "\n";
echo "  时区: " . TIMEZONE . "\n";
echo "  订单过期: " . ORDER_EXPIRE_SECONDS . "秒\n";
echo "  金额随机: " . AMOUNT_RANDOM_MIN . "~" . AMOUNT_RANDOM_MAX . "元\n";
echo "  回调重试: " . CALLBACK_RETRY . "次\n\n";

// 6. 测试API
echo "[6] API接口列表...\n";
$apis = [
    'POST /api.php?action=order_create'    => '创建订单',
    'POST /api.php?action=order_query'     => '查询订单',
    'POST /api.php?action=monitor_report'  => '监控端上报',
    'GET  /api.php?action=health'          => '健康检查',
    'GET  /api.php?action=stats'           => '统计数据',
    'GET  /pay.php?trade_no=xxx'           => '支付页面',
    'GET  /check.php?trade_no=xxx'         => '状态轮询',
    'GET  /admin.php'                      => '管理后台',
];
foreach ($apis as $url => $desc) {
    echo "  {$url} — {$desc}\n";
}
echo "\n";

echo "══════════════════════════════════════════\n";
echo "  ✅ 初始化完成!\n";
echo "══════════════════════════════════════════\n";
echo "\n";
echo "下一步:\n";
echo "  1. 访问管理后台: " . SITE_URL . "/admin.php\n";
echo "  2. 把微信收款码图片放到 data/wechat_qr.png\n";
echo "  3. 配置PC监控端指向: " . SITE_URL . "/api.php?action=monitor_report\n";
echo "  4. 监控端密钥(mapay_monitor_2024)需与服务端一致\n";
