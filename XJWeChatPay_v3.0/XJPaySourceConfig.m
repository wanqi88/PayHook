//
//  XJPaySourceConfig.m
//  XJWeChatPay — 收款来源白名单实现
//

#import "XJPaySourceConfig.h"

@interface XJPaySourceConfig ()
@property (nonatomic, strong) NSArray<NSString *> *currentSources;
@property (nonatomic, strong) NSSet<NSString *> *sourceSet; // O(1) 查找
@end

@implementation XJPaySourceConfig

+ (instancetype)sharedInstance {
    static XJPaySourceConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XJPaySourceConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 内置默认白名单
        self.currentSources = @[
            @"gh_3dfda90e39d6",   // 微信支付
            @"gh_f0a92aa7146c",   // 微信收款助手
            @"filehelper",         // 文件传输助手（个人收款提醒）
        ];
        [self rebuildSet];
    }
    return self;
}

- (BOOL)isPaymentSource:(NSString *)fromUser {
    if (!fromUser || fromUser.length == 0) return NO;

    // 精确匹配
    if ([self.sourceSet containsObject:fromUser]) return YES;

    // 模糊匹配：包含 "pay" 且同时含 "收款"/"到账" 关键词的也视为可疑来源
    // （由调用方结合内容判断，此处只做白名单精确匹配）
    return NO;
}

- (void)updateSources:(NSArray<NSString *> *)sourceIds {
    if (!sourceIds || sourceIds.count == 0) return;
    self.currentSources = [sourceIds copy];
    [self rebuildSet];
    NSLog(@"[XJPay][Source] Whitelist updated: %lu sources",
          (unsigned long)sourceIds.count);
}

- (void)rebuildSet {
    self.sourceSet = [NSSet setWithArray:self.currentSources];
}

@end
