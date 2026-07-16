//
//  XJPaySourceConfig.h
//  XJWeChatPay — 收款来源公众号白名单
//
//  通过白名单精准识别微信支付/收款助手等公众号来源。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XJPaySourceConfig : NSObject

+ (instancetype)sharedInstance;

/// 检查发送者是否为已知收款通知来源
/// @param fromUser m_nsFromUsr（wxid 或 gh_xxx）
- (BOOL)isPaymentSource:(NSString *)fromUser;

/// 更新白名单（通常由 XJRemoteConfig 调用）
- (void)updateSources:(NSArray<NSString *> *)sourceIds;

/// 当前白名单
@property (nonatomic, strong, readonly) NSArray<NSString *> *currentSources;

@end

NS_ASSUME_NONNULL_END
