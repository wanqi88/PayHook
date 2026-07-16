//
//  XJMessageDedup.h
//  XJWeChatPay — 基于服务器消息ID的去重
//
//  利用 m_n64MesSvrID 做精准去重，避免 Hook 多点触发导致重复上报。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XJMessageDedup : NSObject

+ (instancetype)sharedInstance;

/// 检查消息是否已处理（基于服务器消息ID）
/// @param svrMsgId m_n64MesSvrID
/// @return YES 表示重复，应跳过
- (BOOL)isDuplicate:(long long)svrMsgId;

/// 记录已处理的消息
- (void)recordMessage:(long long)svrMsgId;

/// 清空去重缓存
- (void)clearCache;

/// 当前缓存条目数
@property (nonatomic, assign, readonly) NSUInteger cacheCount;

@end

NS_ASSUME_NONNULL_END
