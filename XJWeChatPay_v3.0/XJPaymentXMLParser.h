//
//  XJPaymentXMLParser.h
//  XJWeChatPay — 微信支付消息 XML 深度解析器
//
//  使用 NSXMLParser 从 m_nsContent XML 中提取支付详情。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 支付 XML 解析结果
/// 解析 <msg><appmsg><wcpayinfo> 中的字段
@interface XJPaymentXMLResult : NSObject

@property (nonatomic, copy, nullable) NSString *appmsgType;        // <type>2000</type> — 2000=转账/收款
@property (nonatomic, copy, nullable) NSString *title;             // <title>微信转账</title>
@property (nonatomic, copy, nullable) NSString *des;               // <des>收到转账0.01元...</des>
@property (nonatomic, copy, nullable) NSString *paysubtype;        // 1=转账, 3=收款回执
@property (nonatomic, copy, nullable) NSString *feedesc;           // 金额显示 "￥0.01"
@property (nonatomic, copy, nullable) NSString *transcationid;     // 交易ID
@property (nonatomic, copy, nullable) NSString *transferid;        // 转账ID
@property (nonatomic, copy, nullable) NSString *invalidtime;       // 过期时间
@property (nonatomic, copy, nullable) NSString *begintransfertime; // 转账开始时间
@property (nonatomic, copy, nullable) NSString *effectivedate;     // 有效天数
@property (nonatomic, copy, nullable) NSString *payMemo;           // 备注 "转账给你"

/// 是否成功解析到支付信息
@property (nonatomic, readonly) BOOL hasPayInfo;

@end


/// XML 解析器 — 线程安全，建议后台线程使用
@interface XJPaymentXMLParser : NSObject

/// 从 XML 字符串解析支付信息
/// @param xmlString m_nsContent 原始 XML
/// @return 解析结果，无支付信息时返回 nil
+ (nullable XJPaymentXMLResult *)parse:(NSString *)xmlString;

/// 快速检查是否包含支付 XML
+ (BOOL)isPaymentXML:(NSString *)xmlString;

@end

NS_ASSUME_NONNULL_END
