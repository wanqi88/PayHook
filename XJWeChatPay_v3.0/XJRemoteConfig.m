//
//  XJRemoteConfig.m
//  XJWeChatPay — 远程配置实现
//

#import "XJRemoteConfig.h"

/// 远程配置 URL（可从本地 plist 覆盖）
static NSString *kRemoteConfigURL = @"https://raw.githubusercontent.com/curtinlv/XJWeChatPay-config/main/config.json";

/// 本地缓存路径
static NSString *kLocalCachePath = @"/var/mobile/Library/Preferences/com.xj.wechatpay.remote.plist";

/// 默认更新间隔：1 小时
static NSTimeInterval kDefaultUpdateInterval = 3600.0;

@interface XJRemoteConfig ()
@property (nonatomic, strong) NSArray<NSString *> *paymentKeywords;
@property (nonatomic, strong) NSArray<NSString *> *amountRegexes;
@property (nonatomic, strong) NSArray<NSString *> *paySourceIds;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *payTypeMapping;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;
@property (nonatomic, copy) NSString *configVersion;
@end

@implementation XJRemoteConfig

+ (instancetype)sharedInstance {
    static XJRemoteConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XJRemoteConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadDefaults];
    }
    return self;
}

#pragma mark - Defaults

- (void)loadDefaults {
    // 内置默认配置 — 即使远程拉取失败也能正常工作
    self.paymentKeywords = @[
        @"收款到账通知", @"收款金额", @"到账金额", @"收款成功",
        @"微信支付收款", @"朋友到店付款", @"已存入零钱",
        @"个人收款码到账", @"二维码收款到账", @"收款小账本",
        @"paymsg", @"delpaymsg", @"wxpay", @"微信转账",
        @"收到转账", @"已收款", @"付款成功"
    ];

    self.amountRegexes = @[
        @"收款(?:金额|到账|成功)[:：\\s]*[￥¥]?\\s*([0-9]+\\.?[0-9]{0,2})\\s*元?",
        @"到账金额[:：\\s]*[￥¥]?\\s*([0-9]+\\.?[0-9]{0,2})\\s*元?",
        @"实收金额[:：\\s]*[￥¥]?\\s*([0-9]+\\.?[0-9]{0,2})",
        @"<amount>([0-9]+)</amount>",
        @"<des>[^<]*?([0-9]+\\.?[0-9]{0,2})\\s*元[^<]*?</des>",
        @"付款\\s*([0-9]+\\.?[0-9]{0,2})\\s*元",
        @"([0-9]+\\.[0-9]{1,2})\\s*元",
        @"[￥¥]\\s*([0-9]+\\.?[0-9]{0,2})",
        @"收到转账\\s*([0-9]+\\.?[0-9]{0,2})\\s*元",
    ];

    self.paySourceIds = @[
        @"gh_3dfda90e39d6",   // 微信支付
        @"gh_f0a92aa7146c",   // 微信收款助手
        @"filehelper",         // 文件传输助手（个人收款提醒）
    ];

    self.payTypeMapping = @{
        @"1":    @"transfer",              // 转账
        @"3":    @"receive_confirm",       // 收款回执
        @"2000": @"transfer",              // appmsg type=2000 转账
    };
}

#pragma mark - Local Cache

- (void)loadLocalCache {
    NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:kLocalCachePath];
    if (!cache) return;

    [self applyConfig:cache];
    NSLog(@"[XJPay][Config] Loaded local cache, version=%@", self.configVersion);
}

- (void)saveLocalCache:(NSDictionary *)config {
    [config writeToFile:kLocalCachePath atomically:YES];
}

#pragma mark - Remote Fetch

- (void)fetchRemoteConfig {
    // 读取本地 plist 中配置的 URL（允许用户自定义）
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
                           @"/var/mobile/Library/Preferences/com.xj.wechatpay.plist"];
    NSString *urlStr = prefs[@"remote_config_url"];
    if (!urlStr || urlStr.length == 0) {
        urlStr = kRemoteConfigURL;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *url = [NSURL URLWithString:urlStr];
        NSURLRequest *request = [NSURLRequest requestWithURL:url
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:15.0];

        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

            if (error || !data) {
                NSLog(@"[XJPay][Config] Remote fetch failed: %@, using local cache",
                      error.localizedDescription);
                return;
            }

            NSError *jsonErr = nil;
            NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:0
                                                                     error:&jsonErr];
            if (jsonErr || !config) {
                NSLog(@"[XJPay][Config] JSON parse failed: %@", jsonErr.localizedDescription);
                return;
            }

            // 版本检查：跳过旧版本
            NSString *remoteVersion = config[@"version"];
            if (remoteVersion && self.configVersion) {
                if ([remoteVersion compare:self.configVersion options:NSNumericSearch] != NSOrderedDescending) {
                    // 已经是最新或更新版本，但允许覆盖
                }
            }

            [self applyConfig:config];
            [self saveLocalCache:config];

            NSLog(@"[XJPay][Config] Remote config loaded: version=%@, keywords=%lu, sources=%lu",
                  remoteVersion,
                  (unsigned long)self.paymentKeywords.count,
                  (unsigned long)self.paySourceIds.count);
        }];

        [task resume];
    });
}

- (void)forceRefresh {
    self.configVersion = nil;
    self.lastUpdateTime = 0;
    [self fetchRemoteConfig];
}

#pragma mark - Config Application

- (void)applyConfig:(NSDictionary *)config {
    // 关键词
    NSArray *keywords = config[@"payment_keywords"];
    if (keywords && [keywords isKindOfClass:[NSArray class]] && keywords.count > 0) {
        self.paymentKeywords = keywords;
    }

    // 金额正则
    NSArray *regexes = config[@"amount_regexes"];
    if (regexes && [regexes isKindOfClass:[NSArray class]] && regexes.count > 0) {
        self.amountRegexes = regexes;
    }

    // 公众号白名单
    NSArray *sources = config[@"pay_source_ids"];
    if (sources && [sources isKindOfClass:[NSArray class]] && sources.count > 0) {
        self.paySourceIds = sources;
    }

    // payType 映射
    NSDictionary *mapping = config[@"pay_type_mapping"];
    if (mapping && [mapping isKindOfClass:[NSDictionary class]] && mapping.count > 0) {
        self.payTypeMapping = mapping;
    }

    // 元信息
    self.configVersion = config[@"version"];
    self.lastUpdateTime = [[NSDate date] timeIntervalSince1970];
}

@end
