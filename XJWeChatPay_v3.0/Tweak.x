//
//  Tweak.x
//  XJWeChatPay v3.0 — 微信收款监控（增强版）
//
// 增强模块:
//    - XML 深度解析 (XJPaymentXMLParser)
//    - 远程配置热更新 (XJRemoteConfig)
//    - 公众号白名单精准识别 (XJPaySourceConfig)
//    - 服务器消息ID去重 (XJMessageDedup)
//    - CMessageMgr 多组 Hook 兼容
//    - 联系人信息增强
//    - 扩展 CMessageWrap 字段提取
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
// MARK: - Import Enhanced Modules
// ============================================================

#import "XJPaymentXMLParser.h"
#import "XJRemoteConfig.h"
#import "XJPaySourceConfig.h"
#import "XJMessageDedup.h"

// ============================================================
// MARK: - Configuration
// ============================================================

static NSString *kServerURL     = nil;
static NSString *kMonitorSecret = nil;
static NSString *kMonitorName   = nil;
static BOOL      kDebugEnabled  = YES;
static NSTimeInterval kDedupWindow = 30.0;
static BOOL      kVisualFeedback = YES;

static NSMutableDictionary *sReportedAmounts = nil;

static NSInteger sHookFiredCount    = 0;
static NSInteger sPaymentDetected   = 0;
static NSInteger sReportSent        = 0;
static NSInteger sReportMatched     = 0;
static NSInteger sReportFailed      = 0;
static NSInteger sMessageWrapFired  = 0;
static NSInteger sCMessageMgrFired  = 0;  // 新增：CMessageMgr Hook 计数
static NSInteger sDedupSkipped      = 0;  // 新增：去重跳过计数
static NSInteger sXMLParsed         = 0;  // 新增：XML 解析成功计数
static NSInteger sSourceMatched     = 0;  // 新增：白名单匹配计数
static NSString *sLastMatchTradeNo  = nil;
static NSString *sLastMatchAmount   = nil;
static NSTimeInterval sLastReportTime = 0;
static NSString *sLastDetectionMethod = nil; // 新增：最近检测方法

// ============================================================
// MARK: - Recent Message Log (enhanced)
// ============================================================

typedef struct {
    NSTimeInterval timestamp;
    unsigned int   msgType;
    unsigned int   appMsgInnerType;
    char           fromUser[64];
    char           contentPreview[200];  // 扩展到 200 字符
    BOOL           isPayment;
    char           amount[16];
    char           detectionMethod[32];   // 新增：检测方法
    char           paysubtype[8];         // 新增：支付子类型
    char           transcationid[64];     // 新增：交易ID
} XJMessageLogEntry;

#define kMaxMsgLogEntries 20
static XJMessageLogEntry sMsgLog[kMaxMsgLogEntries];
static int sMsgLogCount = 0;
static int sMsgLogIndex = 0;

static void XJLogMessage(unsigned int msgType,
                         unsigned int appMsgInnerType,
                         NSString *fromUser,
                         NSString *content,
                         BOOL isPayment,
                         NSString *amount,
                         NSString *detectionMethod,
                         NSString *paysubtype,
                         NSString *transcationid) {
    int idx = sMsgLogIndex;
    sMsgLog[idx].timestamp = [[NSDate date] timeIntervalSince1970];
    sMsgLog[idx].msgType = msgType;
    sMsgLog[idx].appMsgInnerType = appMsgInnerType;
    sMsgLog[idx].isPayment = isPayment;

    const char *from = fromUser ? [fromUser UTF8String] : "";
    strncpy(sMsgLog[idx].fromUser, from, 63);
    sMsgLog[idx].fromUser[63] = '\0';

    NSString *preview = content;
    if (preview.length > 199) preview = [preview substringToIndex:199];
    preview = [preview stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    const char *cstr = [preview UTF8String];
    strncpy(sMsgLog[idx].contentPreview, cstr, 199);
    sMsgLog[idx].contentPreview[199] = '\0';

    const char *amt = amount ? [amount UTF8String] : "";
    strncpy(sMsgLog[idx].amount, amt, 15);
    sMsgLog[idx].amount[15] = '\0';

    const char *dm = detectionMethod ? [detectionMethod UTF8String] : "";
    strncpy(sMsgLog[idx].detectionMethod, dm, 31);
    sMsgLog[idx].detectionMethod[31] = '\0';

    const char *ps = paysubtype ? [paysubtype UTF8String] : "";
    strncpy(sMsgLog[idx].paysubtype, ps, 7);
    sMsgLog[idx].paysubtype[7] = '\0';

    const char *tx = transcationid ? [transcationid UTF8String] : "";
    strncpy(sMsgLog[idx].transcationid, tx, 63);
    sMsgLog[idx].transcationid[63] = '\0';

    sMsgLogIndex = (sMsgLogIndex + 1) % kMaxMsgLogEntries;
    if (sMsgLogCount < kMaxMsgLogEntries) sMsgLogCount++;
}

// ============================================================
// MARK: - WeChat Private Class Declarations
// ============================================================

// --- CMessageWrap (扩展) ---
@interface CMessageWrap : NSObject
@property (retain, nonatomic) NSString     *m_nsContent;
@property (retain, nonatomic) NSString     *m_nsTitle;
@property (retain, nonatomic) NSString     *m_nsDesc;
@property (retain, nonatomic) NSString     *m_nsFromUsr;
@property (retain, nonatomic) NSString     *m_nsToUsr;
@property (retain, nonatomic) NSString     *m_nsMsgSource;
@property (assign, nonatomic) unsigned int  m_uiMessageType;
@property (assign, nonatomic) NSInteger     m_nMsgStatus;
@property (assign, nonatomic) long long     m_n64MesSvrID;       // 新增
@property (assign, nonatomic) NSUInteger    m_uiCreateTime;       // 新增
@property (assign, nonatomic) NSUInteger    m_uiAppMsgInnerType;  // 新增
@property (retain, nonatomic) NSString     *m_nsRealChatUsr;      // 新增
@property (retain, nonatomic) id            m_oWCPayInfoItem;     // 新增：WCPayInfoItem
@end

// --- WCPayInfoItem ---
@interface WCPayInfoItem : NSObject
@property (retain, nonatomic) NSString *m_c2cNativeUrl;
@end

// --- CMessageMgr ---
@interface CMessageMgr : NSObject
- (void)AsyncOnAddMsg:(NSString *)msg MsgWrap:(CMessageWrap *)wrap;
@end

// --- MMServiceCenter ---
@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)service;
@end

// --- CContact / CContactMgr ---
@interface CContact : NSObject
@property (retain, nonatomic) NSString *m_nsUsrName;
@property (retain, nonatomic) NSString *m_nsNickName;
@property (retain, nonatomic) NSString *m_nsHeadImgUrl;
- (id)getContactDisplayName;
@end

@interface CContactMgr : NSObject
- (CContact *)getSelfContact;
- (id)getContactByName:(NSString *)name;
@end

// ============================================================
// MARK: - Visual Helpers (unchanged from v2.2)
// ============================================================

static UIWindow *XJGetActiveWindow(void) {
    UIWindow *topWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.hidden && w.windowLevel == UIWindowLevelNormal) {
                topWindow = w;
                break;
            }
        }
        if (topWindow) break;
    }
    if (!topWindow) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && w.windowLevel == UIWindowLevelNormal) {
                topWindow = w;
                break;
            }
        }
    }
    return topWindow;
}

static UIViewController *XJGetTopVC(void) {
    UIWindow *w = XJGetActiveWindow();
    if (!w) return nil;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void XJShowAlert(NSString *title, NSString *message, BOOL autoDismiss) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = XJGetTopVC();
        if (!topVC) { NSLog(@"[XJPay] No top VC for alert"); return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        if (autoDismiss) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        } else {
            UIAlertAction *ok = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:ok];
        }
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

static void XJShowBanner(NSString *title, NSString *message) {
    if (!kVisualFeedback) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *topWindow = XJGetActiveWindow();
        if (!topWindow) { NSLog(@"[XJPay] No window for banner"); return; }

        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat bannerHeight = 90.0;
        UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(10, 55, screenWidth - 20, bannerHeight)];
        banner.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
        banner.layer.cornerRadius = 12;
        banner.layer.masksToBounds = YES;
        banner.alpha = 0.0;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, banner.frame.size.width - 24, 22)];
        titleLabel.text = title;
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [banner addSubview:titleLabel];

        UILabel *msgLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 32, banner.frame.size.width - 24, 52)];
        msgLabel.text = message;
        msgLabel.textColor = [UIColor colorWithRed:0.75 green:0.95 blue:0.75 alpha:1.0];
        msgLabel.font = [UIFont systemFontOfSize:13];
        msgLabel.numberOfLines = 3;
        [banner addSubview:msgLabel];

        [topWindow addSubview:banner];
        [UIView animateWithDuration:0.3 animations:^{ banner.alpha = 1.0; }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ banner.alpha = 0.0; }
                              completion:^(BOOL f){ [banner removeFromSuperview]; }];
        });
    });
}

// ============================================================
// MARK: - Configuration Loading & Saving
// ============================================================

static NSString *kPrefsPath = @"/var/mobile/Library/Preferences/com.xj.wechatpay.plist";

static void XJLoadConfig(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];

    kServerURL     = prefs[@"server_url"]      ?: @"http://pay.yzfaiu.xyz";
    kMonitorSecret = prefs[@"monitor_secret"]  ?: @"mapay_monitor_2024";
    kMonitorName   = prefs[@"monitor_name"]    ?: @"iOS-Hook-01";

    if (prefs[@"debug"] != nil) kDebugEnabled = [prefs[@"debug"] boolValue];
    if (prefs[@"visual_feedback"] != nil) kVisualFeedback = [prefs[@"visual_feedback"] boolValue];
    if (prefs[@"dedup_window"] != nil) kDedupWindow = [prefs[@"dedup_window"] doubleValue];
    if (kDedupWindow < 5.0) kDedupWindow = 30.0;

    if (!sReportedAmounts) sReportedAmounts = [[NSMutableDictionary alloc] init];
}

static void XJSaveConfig(void) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    prefs[@"server_url"]      = kServerURL;
    prefs[@"monitor_secret"]  = kMonitorSecret;
    prefs[@"monitor_name"]    = kMonitorName;
    prefs[@"debug"]           = @(kDebugEnabled);
    prefs[@"visual_feedback"] = @(kVisualFeedback);
    prefs[@"dedup_window"]    = @(kDedupWindow);
    [prefs writeToFile:kPrefsPath atomically:YES];
    NSLog(@"[XJPay] Config saved to %@", kPrefsPath);
}

// ============================================================
// MARK: - Enhanced Payment Detection
// ============================================================

// 前向声明：原始金额提取（在下方定义）
static NSString *XJExtractAmountLegacy(NSString *content);

/// 增强版收款检测：白名单优先 → XML 确认 → 关键词兜底
static BOOL XJIsPaymentNotificationEnhanced(NSString *content,
                                            NSString *fromUser,
                                            XJPaymentXMLResult *xmlResult) {
    if (!content || content.length == 0) return NO;

    // 层级 1: 公众号白名单（最高置信度）
    if ([[XJPaySourceConfig sharedInstance] isPaymentSource:fromUser]) {
        return YES;
    }

    // 层级 2: XML 结构确认（高置信度）
    if (xmlResult && xmlResult.hasPayInfo) {
        NSString *appmsgType = xmlResult.appmsgType;
        if ([appmsgType isEqualToString:@"2000"]) return YES;  // 转账/收款
        if (xmlResult.paysubtype.length > 0) return YES;       // 有支付子类型
    }

    // 层级 3: 关键词兜底（低置信度，但兼容旧版）
    XJRemoteConfig *config = [XJRemoteConfig sharedInstance];
    for (NSString *kw in config.paymentKeywords) {
        if ([content rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    // 层级 4: 发送者模糊匹配（最低置信度）
    if (fromUser && [[fromUser lowercaseString] containsString:@"pay"]) {
        if ([content containsString:@"收款"] ||
            [content containsString:@"到账"] ||
            [content containsString:@"元"]) return YES;
    }

    return NO;
}

/// 增强版金额提取：XML feedesc 优先 → desc → 正则兜底
static NSString *XJExtractAmountEnhanced(NSString *content,
                                          XJPaymentXMLResult *xmlResult) {
    // 优先级 1: XML <feedesc> 字段（格式固定 "￥0.01"）
    if (xmlResult && xmlResult.feedesc.length > 0) {
        NSString *feedesc = xmlResult.feedesc;
        // 提取 ￥ 后面的数字，支持千分位逗号
        NSRegularExpression *feedescRegex = [NSRegularExpression
            regularExpressionWithPattern:@"[￥¥]\\s*([0-9,]+\\.?[0-9]{0,2})"
            options:0 error:nil];
        NSTextCheckingResult *match = [feedescRegex firstMatchInString:feedesc
                                                               options:0
                                                                 range:NSMakeRange(0, feedesc.length)];
        if (match && match.numberOfRanges > 1) {
            NSString *amountStr = [feedesc substringWithRange:[match rangeAtIndex:1]];
            amountStr = [amountStr stringByReplacingOccurrencesOfString:@"," withString:@""];
            double value = [amountStr doubleValue];
            if (value >= 0.01 && value < 100000.0) return [NSString stringWithFormat:@"%.2f", value];
        }
    }

    // 优先级 2: XML <des> 字段
    if (xmlResult && xmlResult.des.length > 0) {
        NSString *desc = xmlResult.des;
        NSRegularExpression *descRegex = [NSRegularExpression
            regularExpressionWithPattern:@"([0-9]+\\.[0-9]{1,2})\\s*元"
            options:0 error:nil];
        NSTextCheckingResult *match = [descRegex firstMatchInString:desc
                                                            options:0
                                                              range:NSMakeRange(0, desc.length)];
        if (match && match.numberOfRanges > 1) {
            NSString *amountStr = [desc substringWithRange:[match rangeAtIndex:1]];
            double value = [amountStr doubleValue];
            if (value >= 0.01 && value < 100000.0) return [NSString stringWithFormat:@"%.2f", value];
        }
    }

    // 优先级 3: 原始正则匹配（兜底）
    return XJExtractAmountLegacy(content);
}

/// 原始正则（保留作为兜底）
static NSString *XJExtractAmountLegacy(NSString *content) {
    if (!content || content.length == 0) return nil;

    XJRemoteConfig *config = [XJRemoteConfig sharedInstance];

    for (NSString *pattern in config.amountRegexes) {
        NSError *err = nil;
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:pattern
            options:NSRegularExpressionCaseInsensitive error:&err];
        if (err || !regex) continue;
        NSTextCheckingResult *match = [regex firstMatchInString:content
                                                        options:0
                                                          range:NSMakeRange(0, content.length)];
        if (match && match.numberOfRanges > 1) {
            NSString *amountStr = [content substringWithRange:[match rangeAtIndex:1]];
            double value = [amountStr doubleValue];
            if ([pattern containsString:@"<amount>"]) value = value / 100.0;
            if (value >= 0.01 && value < 100000.0) return [NSString stringWithFormat:@"%.2f", value];
        }
    }
    return nil;
}

/// 时间窗口去重（保留 v2.2 逻辑）
static BOOL XJShouldReport(NSString *amount) {
    @synchronized(sReportedAmounts) {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSMutableArray *expired = [NSMutableArray array];
        [sReportedAmounts enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSNumber *t, BOOL *stop){
            if ((now - [t doubleValue]) > kDedupWindow) [expired addObject:k];
        }];
        for (NSString *k in expired) [sReportedAmounts removeObjectForKey:k];
        if (sReportedAmounts[amount]) return NO;
        sReportedAmounts[amount] = @(now);
        return YES;
    }
}

// ============================================================
// MARK: - Contact Info Enhancement
// ============================================================

static NSDictionary *XJGetContactInfo(NSString *userName) {
    if (!userName || userName.length == 0) return nil;

    @try {
        Class contactMgrClass = objc_getClass("CContactMgr");
        Class serviceCenterClass = objc_getClass("MMServiceCenter");
        if (!contactMgrClass || !serviceCenterClass) return nil;

        id contactMgr = [[serviceCenterClass defaultCenter] getService:contactMgrClass];
        if (!contactMgr) return nil;

        id contact = [contactMgr getContactByName:userName];
        if (!contact) return nil;

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        NSString *nick = [contact valueForKey:@"m_nsNickName"];
        NSString *headImg = [contact valueForKey:@"m_nsHeadImgUrl"];
        id displayName = [contact getContactDisplayName];

        if (nick) info[@"nick_name"] = nick;
        if (headImg) info[@"head_img_url"] = headImg;
        if (displayName) info[@"display_name"] = [displayName description];

        return info.count > 0 ? info : nil;
    } @catch (NSException *e) {
        NSLog(@"[XJPay] Contact lookup failed for %@: %@", userName, e.reason);
        return nil;
    }
}

// ============================================================
// MARK: - Enhanced HTTP Reporting
// ============================================================

static void XJReportPaymentEnhanced(NSString *amount,
                                     NSString *rawText,
                                     NSDictionary *extraFields) {
    if (!XJShouldReport(amount)) {
        NSLog(@"[XJPay] SKIP (dedup) amount=%@", amount);
        return;
    }

    sReportSent++;
    sLastReportTime = [[NSDate date] timeIntervalSince1970];

    // 构建增强上报数据
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"amount":         @([amount doubleValue]),
        @"pay_type":       extraFields[@"pay_type"] ?: @"wechat",
        @"raw_text":       rawText.length > 500 ? [rawText substringToIndex:500] : rawText,
        @"timestamp":      [NSString stringWithFormat:@"%ld", (long)sLastReportTime],
        @"monitor":        kMonitorName ?: @"iOS-Hook-01",
        @"source":         @"ios_hook",
        @"monitor_secret": kMonitorSecret ?: @"mapay_monitor_2024",
    }];

    // 添加增强字段（仅在非空时添加）
    NSArray *extraKeys = @[@"msg_type", @"app_msg_inner_type", @"from_user", @"to_user",
                           @"real_sender", @"svr_msg_id", @"server_timestamp",
                           @"paysubtype", @"transcationid", @"transferid", @"pay_memo",
                           @"native_url", @"detection_method", @"contact_nick",
                           @"contact_head_img", @"contact_display_name"];
    for (NSString *key in extraKeys) {
        id val = extraFields[key];
        if (val) params[key] = val;
    }

    NSString *urlStr = [NSString stringWithFormat:@"%@/api.php?action=monitor_report",
                        kServerURL ?: @"http://pay.yzfaiu.xyz"];
    NSURL *url = [NSURL URLWithString:urlStr];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 10.0;

    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonErr];
    if (jsonErr) {
        sReportFailed++;
        XJShowBanner(@"XJPay 错误", @"JSON序列化失败");
        return;
    }
    request.HTTPBody = jsonData;

    NSLog(@"[XJPay] >>> Enhanced report: amount=%@ type=%@ method=%@ txid=%@",
          amount,
          params[@"pay_type"],
          params[@"detection_method"],
          params[@"transcationid"]);
    XJShowBanner(@"XJPay 检测到收款",
                 [NSString stringWithFormat:@"金额: %@ 元 - 正在上报...", amount]);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    sReportFailed++;
                    NSLog(@"[XJPay] Report FAILED: %@", error.localizedDescription);
                    XJShowBanner(@"XJPay 上报失败", error.localizedDescription);
                    return;
                }
                NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[XJPay] Server response: %@", respStr);
                NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (!result) {
                    sReportFailed++;
                    XJShowBanner(@"XJPay 错误", @"服务端返回非JSON数据");
                    return;
                }
                NSInteger code = [result[@"code"] integerValue];
                BOOL matched = [result[@"matched"] boolValue];
                NSString *tradeNo = result[@"trade_no"] ?: @"";
                NSString *respMsg = result[@"msg"] ?: @"";

                if (code == 200 && matched) {
                    sReportMatched++;
                    sLastMatchTradeNo = [tradeNo copy];
                    sLastMatchAmount = [amount copy];
                    XJShowAlert(@"支付成功",
                                [NSString stringWithFormat:@"收款 %@ 元\n订单已匹配\n订单号: %@", amount, tradeNo], NO);
                } else if (code == 200 && !matched) {
                    XJShowBanner(@"XJPay 已上报",
                                 [NSString stringWithFormat:@"%@ 元 - 暂无匹配订单", amount]);
                } else if (code == 200) {
                    NSLog(@"[XJPay] Deduplicated by server: %@", amount);
                } else {
                    sReportFailed++;
                    XJShowBanner(@"XJPay 服务端错误",
                                 [NSString stringWithFormat:@"code=%ld %@", (long)code, respMsg]);
                }
            }];
        [task resume];
    });
}

// ============================================================
// MARK: - Unified Message Processing (Enhanced)
// ============================================================

/// 统一消息处理入口（被 setM_nsContent 和 AsyncOnAddMsg 共用）
static void XJProcessMessageEnhanced(id rawMsg, NSString *caller) {
    @try {
        // --- 提取完整字段 ---
        NSString *content    = [rawMsg valueForKey:@"m_nsContent"];
        unsigned int msgType = [[rawMsg valueForKey:@"m_uiMessageType"] unsignedIntValue];
        NSString *fromUser   = [rawMsg valueForKey:@"m_nsFromUsr"];
        NSString *toUser     = [rawMsg valueForKey:@"m_nsToUsr"];
        NSString *desc       = [rawMsg valueForKey:@"m_nsDesc"];
        NSString *title      = [rawMsg valueForKey:@"m_nsTitle"];

        // 新增字段
        long long svrMsgId         = [[rawMsg valueForKey:@"m_n64MesSvrID"] longLongValue];
        NSUInteger createTime      = [[rawMsg valueForKey:@"m_uiCreateTime"] unsignedIntegerValue];
        NSUInteger appMsgInnerType = [[rawMsg valueForKey:@"m_uiAppMsgInnerType"] unsignedIntegerValue];
        NSString *realChatUsr      = [rawMsg valueForKey:@"m_nsRealChatUsr"];
        NSString *msgSource        = [rawMsg valueForKey:@"m_nsMsgSource"];
        id payItemObj              = [rawMsg valueForKey:@"m_oWCPayInfoItem"];
        NSString *nativeUrl        = [payItemObj valueForKey:@"m_c2cNativeUrl"];

        // --- 拼接完整内容 ---
        NSMutableString *allContent = [NSMutableString string];
        if (content) [allContent appendString:content];
        if (desc && desc.length > 0) [allContent appendFormat:@"|DESC:%@", desc];
        if (title && title.length > 0) [allContent appendFormat:@"|TITLE:%@", title];

        if (allContent.length == 0) return;

        // --- 阶段 1: 消息去重（基于 svrMsgId） ---
        if (svrMsgId > 0) {
            if ([[XJMessageDedup sharedInstance] isDuplicate:svrMsgId]) {
                sDedupSkipped++;
                if (kDebugEnabled) {
                    NSLog(@"[XJPay] DEDUP skip svrMsgId=%lld caller=%@", svrMsgId, caller);
                }
                return;
            }
            [[XJMessageDedup sharedInstance] recordMessage:svrMsgId];
        }

        // --- 阶段 2: XML 解析（后台线程优化） ---
        XJPaymentXMLResult *xmlResult = nil;
        if ([XJPaymentXMLParser isPaymentXML:content]) {
            xmlResult = [XJPaymentXMLParser parse:content];
            if (xmlResult && xmlResult.hasPayInfo) {
                sXMLParsed++;
            }
        }

        // --- 阶段 3: 增强判断 ---
        BOOL isPayment = XJIsPaymentNotificationEnhanced(allContent, fromUser, xmlResult);
        NSString *amount = isPayment ? XJExtractAmountEnhanced(allContent, xmlResult) : nil;

        // --- 确定检测方法 ---
        NSString *detectionMethod = @"none";
        if (isPayment) {
            if ([[XJPaySourceConfig sharedInstance] isPaymentSource:fromUser]) {
                detectionMethod = @"source_whitelist";
                sSourceMatched++;
            } else if (xmlResult && xmlResult.hasPayInfo) {
                detectionMethod = @"xml_parse";
            } else {
                detectionMethod = @"keyword";
            }
        }

        // --- 阶段 4: 确定支付类型 ---
        NSString *payType = @"wechat";
        if (xmlResult && xmlResult.paysubtype) {
            XJRemoteConfig *cfg = [XJRemoteConfig sharedInstance];
            NSString *mapped = cfg.payTypeMapping[xmlResult.paysubtype];
            if (mapped) payType = mapped;
        }

        // --- 阶段 5: 联系人信息（后台获取） ---
        NSDictionary *contactInfo = nil;
        if (isPayment && fromUser.length > 0) {
            contactInfo = XJGetContactInfo(fromUser);
        }

        // --- 记录增强日志 ---
        XJLogMessage(msgType, appMsgInnerType, fromUser, allContent,
                     isPayment, amount, detectionMethod,
                     xmlResult.paysubtype, xmlResult.transcationid);

        if (kDebugEnabled) {
            NSLog(@"[XJPay] MSG type=%u inner=%lu from=%@ payment=%d method=%@ "
                  @"amount=%@ sub=%@ txid=%@ caller=%@",
                  msgType, (unsigned long)appMsgInnerType, fromUser, isPayment,
                  detectionMethod, amount,
                  xmlResult.paysubtype, xmlResult.transcationid, caller);
        }

        // --- 阶段 6: 上报 ---
        if (isPayment) {
            sPaymentDetected++;
            if (amount) {
                // 构建增强额外字段
                NSMutableDictionary *extra = [NSMutableDictionary dictionary];
                extra[@"msg_type"]           = @(msgType);
                extra[@"app_msg_inner_type"] = @(appMsgInnerType);
                extra[@"from_user"]          = fromUser ?: @"";
                extra[@"to_user"]            = toUser ?: @"";
                extra[@"real_sender"]        = realChatUsr ?: @"";
                extra[@"svr_msg_id"]         = @(svrMsgId);
                extra[@"server_timestamp"]   = @(createTime);
                extra[@"paysubtype"]         = xmlResult.paysubtype ?: @"";
                extra[@"transcationid"]      = xmlResult.transcationid ?: @"";
                extra[@"transferid"]         = xmlResult.transferid ?: @"";
                extra[@"pay_memo"]           = xmlResult.payMemo ?: @"";
                extra[@"native_url"]         = nativeUrl ?: @"";
                extra[@"detection_method"]   = detectionMethod;
                extra[@"pay_type"]           = payType;
                if (contactInfo) {
                    extra[@"contact_nick"]          = contactInfo[@"nick_name"] ?: @"";
                    extra[@"contact_head_img"]      = contactInfo[@"head_img_url"] ?: @"";
                    extra[@"contact_display_name"]  = contactInfo[@"display_name"] ?: @"";
                }

                XJShowBanner(@"XJPay 识别到收款",
                             [NSString stringWithFormat:@"金额: %@ 元 [%@]",
                              amount, detectionMethod]);
                XJReportPaymentEnhanced(amount, allContent, extra);
            } else {
                XJShowBanner(@"XJPay 识别到收款", @"但无法提取金额，请检查日志");
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[XJPay] Exception: %@ - %@", e.name, e.reason);
    }
}

// ============================================================
// MARK: - Settings Panel (Enhanced for v3.0)
// ============================================================

static NSString *XJFormatTime(NSTimeInterval ts) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    return [fmt stringFromDate:date];
}

static NSString *XJBuildStatusMessage(void) {
    NSMutableString *msg = [NSMutableString string];

    // --- Stats ---
    [msg appendFormat:@"── 运行统计 (v3.0) ──\n"];
    [msg appendFormat:@"MessageWrap触发: %ld次\n", (long)sMessageWrapFired];
    [msg appendFormat:@"CMessageMgr触发: %ld次\n", (long)sCMessageMgrFired];
    [msg appendFormat:@"去重跳过: %ld次\n", (long)sDedupSkipped];
    [msg appendFormat:@"XML解析成功: %ld次\n", (long)sXMLParsed];
    [msg appendFormat:@"白名单匹配: %ld次\n", (long)sSourceMatched];
    [msg appendFormat:@"检测到收款: %ld次\n", (long)sPaymentDetected];
    [msg appendFormat:@"上报成功: %ld次\n", (long)sReportSent];
    [msg appendFormat:@"匹配订单: %ld次\n", (long)sReportMatched];
    [msg appendFormat:@"上报失败: %ld次\n", (long)sReportFailed];

    if (sLastReportTime > 0) {
        [msg appendFormat:@"最近上报: %@\n", XJFormatTime(sLastReportTime)];
    }
    if (sLastMatchTradeNo) {
        [msg appendFormat:@"最近匹配: %@ 元\n", sLastMatchAmount ?: @"?"];
        [msg appendFormat:@"订单号: %@\n", sLastMatchTradeNo];
    }
    if (sLastDetectionMethod) {
        [msg appendFormat:@"检测方法: %@\n", sLastDetectionMethod];
    }

    [msg appendFormat:@"\n── 当前配置 ──\n"];
    [msg appendFormat:@"服务器: %@\n", kServerURL];
    [msg appendFormat:@"监控名: %@\n", kMonitorName];
    [msg appendFormat:@"密钥: %@\n", kMonitorSecret];
    [msg appendFormat:@"调试: %@\n", kDebugEnabled ? @"开" : @"关"];
    [msg appendFormat:@"弹窗: %@\n", kVisualFeedback ? @"开" : @"关"];
    [msg appendFormat:@"去重: %.0f秒\n", kDedupWindow];

    XJRemoteConfig *cfg = [XJRemoteConfig sharedInstance];
    [msg appendFormat:@"远程配置: %@\n", cfg.configVersion ?: @"未加载"];
    [msg appendFormat:@"关键词数: %lu\n", (unsigned long)cfg.paymentKeywords.count];

    // --- Recent messages ---
    [msg appendFormat:@"\n── 最近消息 (最多20条) ──\n"];
    if (sMsgLogCount == 0) {
        [msg appendString:@"(暂无消息)\n"];
    } else {
        int count = sMsgLogCount;
        int startIdx = (sMsgLogIndex - count + kMaxMsgLogEntries) % kMaxMsgLogEntries;
        for (int i = 0; i < count; i++) {
            int idx = (startIdx + i) % kMaxMsgLogEntries;
            XJMessageLogEntry *entry = &sMsgLog[idx];
            NSString *timeStr = XJFormatTime(entry->timestamp);
            NSString *fromStr = [NSString stringWithUTF8String:entry->fromUser];
            NSString *contentStr = [NSString stringWithUTF8String:entry->contentPreview];
            NSString *amountStr = entry->amount[0] ? [NSString stringWithUTF8String:entry->amount] : nil;
            NSString *methodStr = entry->detectionMethod[0] ? [NSString stringWithUTF8String:entry->detectionMethod] : nil;
            NSString *txStr = entry->transcationid[0] ? [NSString stringWithUTF8String:entry->transcationid] : nil;

            NSString *payMark = entry->isPayment ? @"★收款" : @"  普通";
            NSString *amountMark = amountStr ? [NSString stringWithFormat:@" [%@元]", amountStr] : @"";
            NSString *methodMark = methodStr ? [NSString stringWithFormat:@" {%@}", methodStr] : @"";

            [msg appendFormat:@"[%@] %@ type=%u inner=%u %@%@%@\n",
             timeStr, payMark, entry->msgType, entry->appMsgInnerType, fromStr, amountMark, methodMark];
            [msg appendFormat:@"  → %@\n", contentStr];
            if (txStr) {
                [msg appendFormat:@"  txid: %@\n", txStr];
            }
        }
    }

    return msg;
}

static void XJShowStatusPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = XJGetTopVC();
        if (!topVC) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"XJWeChatPay v3.0 控制面板"
                             message:XJBuildStatusMessage()
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"服务器地址";
            tf.text = kServerURL;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.keyboardType = UIKeyboardTypeURL;
        }];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"监控端名称";
            tf.text = kMonitorName;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = @"监控密钥";
            tf.text = kMonitorSecret;
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];

        // Save config
        UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"保存配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            UITextField *urlField = [alert.textFields objectAtIndex:0];
            UITextField *nameField = [alert.textFields objectAtIndex:1];
            UITextField *secretField = [alert.textFields objectAtIndex:2];

            BOOL changed = NO;
            if (urlField.text.length > 0 && ![urlField.text isEqualToString:kServerURL]) {
                kServerURL = urlField.text;
                changed = YES;
            }
            if (nameField.text.length > 0 && ![nameField.text isEqualToString:kMonitorName]) {
                kMonitorName = nameField.text;
                changed = YES;
            }
            if (secretField.text.length > 0 && ![secretField.text isEqualToString:kMonitorSecret]) {
                kMonitorSecret = secretField.text;
                changed = YES;
            }

            if (changed) {
                XJSaveConfig();
                XJShowBanner(@"配置已保存", [NSString stringWithFormat:@"服务器: %@\n需重启微信生效", kServerURL]);
            } else {
                XJShowBanner(@"配置未变更", @"所有字段与当前一致");
            }
        }];
        [alert addAction:saveAction];

        // Toggle debug
        NSString *debugTitle = kDebugEnabled ? @"关闭调试日志" : @"开启调试日志";
        UIAlertAction *debugAction = [UIAlertAction actionWithTitle:debugTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            kDebugEnabled = !kDebugEnabled;
            XJSaveConfig();
            XJShowBanner(@"调试日志", kDebugEnabled ? @"已开启" : @"已关闭");
        }];
        [alert addAction:debugAction];

        // Toggle visual feedback
        NSString *visualTitle = kVisualFeedback ? @"关闭弹窗提示" : @"开启弹窗提示";
        UIAlertAction *visualAction = [UIAlertAction actionWithTitle:visualTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            kVisualFeedback = !kVisualFeedback;
            XJSaveConfig();
            XJShowBanner(@"弹窗提示", kVisualFeedback ? @"已开启" : @"已关闭");
        }];
        [alert addAction:visualAction];

        // Send test report
        UIAlertAction *testAction = [UIAlertAction actionWithTitle:@"发送测试上报 (0.01元)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSDictionary *testExtra = @{
                @"pay_type": @"wechat",
                @"detection_method": @"test",
                @"from_user": @"test",
            };
            XJReportPaymentEnhanced(@"0.01", @"[TEST] 微信支付收款 ￥0.01", testExtra);
            XJShowBanner(@"测试上报", @"已发送 0.01 元测试到服务端");
        }];
        [alert addAction:testAction];

        // Force refresh remote config
        UIAlertAction *refreshAction = [UIAlertAction actionWithTitle:@"强制刷新远程配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[XJRemoteConfig sharedInstance] forceRefresh];
            XJShowBanner(@"远程配置", @"正在后台刷新...");
        }];
        [alert addAction:refreshAction];

        // Clear message log
        UIAlertAction *clearAction = [UIAlertAction actionWithTitle:@"清空消息记录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            sMsgLogCount = 0;
            sMsgLogIndex = 0;
            memset(sMsgLog, 0, sizeof(sMsgLog));
            XJShowBanner(@"已清空", @"消息记录已清除");
        }];
        [alert addAction:clearAction];

        // Reset stats
        UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"重置统计数据" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            sHookFiredCount = 0;
            sPaymentDetected = 0;
            sReportSent = 0;
            sReportMatched = 0;
            sReportFailed = 0;
            sMessageWrapFired = 0;
            sCMessageMgrFired = 0;
            sDedupSkipped = 0;
            sXMLParsed = 0;
            sSourceMatched = 0;
            [[XJMessageDedup sharedInstance] clearCache];
            XJShowBanner(@"已重置", @"所有统计数据已清零");
        }];
        [alert addAction:resetAction];

        // Close
        UIAlertAction *closeAction = [UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:closeAction];

        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

// ============================================================
// MARK: - Hook Group: CMessageMgr 消息钩子（5 种签名 fallback，兼容多版本微信）
// ============================================================

/// 安全处理消息（所有 hook 共用）
static void XJSafeProcessMsg(id msg) {
    if (!msg) return;
    @try {
        // 守卫：快速检查消息对象是否完整
        id fromUser = [msg valueForKey:@"m_nsFromUsr"];
        id content = [msg valueForKey:@"m_nsContent"];
        if (!fromUser || !content) return;
        sCMessageMgrFired++;
        XJProcessMessageEnhanced(msg, @"CMessageMgr");
    } @catch (NSException *e) {
        // 静默吞掉，防止核心循环崩溃
    }
}

// --- Group A: onNewMessage: (WeChat 7.x) ---
%group HookOnNewMessage
%hook CMessageMgr
- (void)onNewMessage:(NSArray *)messages {
    %orig;
    if (messages && messages.count > 0) {
        for (id msg in messages) XJSafeProcessMsg(msg);
    }
}
%end
%end

// --- Group B: onRecvMsg: ---
%group HookOnRecvMsg
%hook CMessageMgr
- (void)onRecvMsg:(id)msg {
    %orig;
    XJSafeProcessMsg(msg);
}
%end
%end

// --- Group C: AsyncOnAddMsg:MsgWrap: ---
%group HookAsyncOnAddMsgWrap
%hook CMessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgWrap:(id)wrap {
    %orig;
    XJSafeProcessMsg(wrap);
}
%end
%end

// --- Group D: AsyncOnAddMsg:MsgType: (旧版) ---
%group HookAsyncOnAddMsgType
%hook CMessageMgr
- (void)AsyncOnAddMsg:(id)msg MsgType:(int)type {
    %orig;
    XJSafeProcessMsg(msg);
}
%end
%end

// --- Group E: MessageSyncDidProcess: ---
%group HookSyncProcess
%hook CMessageMgr
- (void)MessageSyncDidProcess:(NSArray *)messages {
    %orig;
    if (messages && messages.count > 0) {
        for (id msg in messages) XJSafeProcessMsg(msg);
    }
}
%end
%end

// --- Group F: MainDispatcherOnAddMsg: ---
%group HookMainDispatcher
%hook CMessageMgr
- (void)MainDispatcherOnAddMsg:(id)msg {
    %orig;
    XJSafeProcessMsg(msg);
}
%end
%end

// ============================================================
// MARK: - Settings Page Trigger: 连点标题 5 次打开控制面板（v2.0 方式，最轻量）
// ============================================================

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    static NSInteger tapCount = 0;
    static NSTimeInterval lastTap = 0;

    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"Setting"] || [className containsString:@"About"]) {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - lastTap > 2.0) tapCount = 0;
        tapCount++;
        lastTap = now;

        if (tapCount >= 5) {
            tapCount = 0;
            XJShowStatusPanel();
        }
    }
}

%end

// ============================================================
// MARK: - Constructor
// ============================================================

%ctor {
    @autoreleasepool {
        XJLoadConfig();

        NSLog(@"[XJPay] ============================================");
        NSLog(@"[XJPay]   XJWeChatPay v3.0.0 Loaded");
        NSLog(@"[XJPay]   Server:  %@", kServerURL);
        NSLog(@"[XJPay]   Monitor: %@", kMonitorName);
        NSLog(@"[XJPay]   Debug:   %@", kDebugEnabled ? @"ON" : @"OFF");
        NSLog(@"[XJPay] ============================================");

        // 初始化所有 CMessageMgr hook groups（至少一种能命中）
        %init(HookOnNewMessage);
        %init(HookOnRecvMsg);
        %init(HookAsyncOnAddMsgWrap);
        %init(HookAsyncOnAddMsgType);
        %init(HookSyncProcess);
        %init(HookMainDispatcher);
        %init;  // UIViewController tap trigger

        NSLog(@"[XJPay] All hooks initialized");

        // 延迟执行重操作：远程配置 + 诊断
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @try {
                [[XJRemoteConfig sharedInstance] loadLocalCache];
                [[XJRemoteConfig sharedInstance] fetchRemoteConfig];
                [[XJPaySourceConfig sharedInstance] updateSources:
                 [XJRemoteConfig sharedInstance].paySourceIds];

                // 诊断：打印 CMessageMgr 可用方法
                Class mgrClass = objc_getClass("CMessageMgr");
                if (mgrClass) {
                    unsigned int mc = 0;
                    Method *methods = class_copyMethodList(mgrClass, &mc);
                    NSMutableArray *msgMethods = [NSMutableArray array];
                    for (unsigned int i = 0; i < mc && i < 200; i++) {
                        NSString *sel = NSStringFromSelector(method_getName(methods[i]));
                        if ([sel containsString:@"Msg"] || [sel containsString:@"Message"]) {
                            [msgMethods addObject:sel];
                        }
                    }
                    free(methods);
                    NSLog(@"[XJPay] CMessageMgr Msg methods: %@", msgMethods);
                }
            } @catch (NSException *e) {
                NSLog(@"[XJPay] Init error: %@", e);
            }

            // 加载提示（延迟到 UI 稳定后）
            dispatch_async(dispatch_get_main_queue(), ^{
                XJRemoteConfig *cfg = [XJRemoteConfig sharedInstance];
                XJShowBanner(@"XJWeChatPay v3.0 已加载",
                             [NSString stringWithFormat:
                              @"连点设置页5次打开控制面板\n"
                              @"远程配置: %@ | 关键词: %lu",
                              cfg.configVersion ?: @"默认",
                              (unsigned long)cfg.paymentKeywords.count]);
            });
        });
    }
}
