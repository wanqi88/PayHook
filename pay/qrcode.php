<?php
/**
 * MaPay 码支付 - 二维码生成
 * ========================
 * 生成二维码图片 (用于占位收款码)
 * 访问: /qrcode.php?text=xxx&size=300
 */

require_once __DIR__ . '/config.php';

$text = $_GET['text'] ?? 'MaPay';
$size = (int)($_GET['size'] ?? 300);

// 使用在线API生成二维码 (无需额外PHP扩展)
// 如果服务器有phpqrcode或GD库，可以本地生成
$url = 'https://api.qrserver.com/v1/create-qr-code/?size=' . $size . 'x' . $size . '&data=' . urlencode($text);

// 尝试下载
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 10,
    CURLOPT_FOLLOWLOCATION => true,
]);
$img = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode === 200 && $img) {
    header('Content-Type: image/png');
    header('Cache-Control: public, max-age=86400');
    echo $img;
} else {
    // 生成简单的SVG占位图
    header('Content-Type: image/svg+xml');
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="' . $size . '" height="' . $size . '">';
    echo '<rect width="100%" height="100%" fill="#fff" stroke="#07c160" stroke-width="4"/>';
    echo '<text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#07c160" font-size="16">扫码支付</text>';
    echo '</svg>';
}
