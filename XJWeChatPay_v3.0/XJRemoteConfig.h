//
//  XJRemoteConfig.h
//  XJWeChatPay — 远程配置热更新
//
//  支持从远程 URL 拉取 JSON 配置，实现关键词/正则/白名单热更新。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XJRemoteConfig : NSObject

+ (instancetype)sharedInstance;

#pragma mark - 配置字段（远程可更新）

/// 收款关键词列表
@property (nonatomic, strong, readonly) NSArray<NSString *> *paymentKeywords;

/// 金额提取正则列表
@property (nonatomic, strong, readonly) NSArray<NSString *> *amountRegexes;

/// 收款来源公众号 ID 白名单
@property (nonatomic, strong, readonly) NSArray<NSString *> *paySourceIds;

/// paysubtype → pay_type 映射 (如 "1" → "transfer", "3" → "receive_confirm")
@property (nonatomic, strong, readonly) NSDictionary<NSString *, NSString *> *payTypeMapping;

/// 最后更新时间
@property (nonatomic, assign, readonly) NSTimeInterval lastUpdateTime;

/// 远程配置版本
@property (nonatomic, copy, readonly, nullable) NSString *configVersion;

#pragma mark - 操作

/// 加载本地缓存（同步，构造函数中调用）
- (void)loadLocalCache;

/// 异步拉取远程配置（成功则覆盖本地缓存）
- (void)fetchRemoteConfig;

/// 强制刷新（忽略更新间隔）
- (void)forceRefresh;

@end

NS_ASSUME_NONNULL_END
