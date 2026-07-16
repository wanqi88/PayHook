//
//  XJMessageDedup.m
//  XJWeChatPay — 消息去重实现（基于 NSCache + NSMutableSet）
//

#import "XJMessageDedup.h"

/// 最大缓存条目数
static const NSUInteger kMaxCacheSize = 200;

@interface XJMessageDedup ()
@property (nonatomic, strong) NSMutableOrderedSet<NSNumber *> *processedIds;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation XJMessageDedup

+ (instancetype)sharedInstance {
    static XJMessageDedup *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XJMessageDedup alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processedIds = [[NSMutableOrderedSet alloc] initWithCapacity:kMaxCacheSize];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)isDuplicate:(long long)svrMsgId {
    if (svrMsgId <= 0) return NO; // 无服务器ID的不去重

    NSNumber *key = @(svrMsgId);
    [self.lock lock];
    BOOL exists = [self.processedIds containsObject:key];
    [self.lock unlock];
    return exists;
}

- (void)recordMessage:(long long)svrMsgId {
    if (svrMsgId <= 0) return;

    NSNumber *key = @(svrMsgId);
    [self.lock lock];

    // 如果已存在，移到最前面（LRU）
    [self.processedIds removeObject:key];

    // 超过上限时移除最旧的
    while (self.processedIds.count >= kMaxCacheSize) {
        [self.processedIds removeObjectAtIndex:0];
    }

    [self.processedIds addObject:key];
    [self.lock unlock];
}

- (void)clearCache {
    [self.lock lock];
    [self.processedIds removeAllObjects];
    [self.lock unlock];
}

- (NSUInteger)cacheCount {
    [self.lock lock];
    NSUInteger count = self.processedIds.count;
    [self.lock unlock];
    return count;
}

@end
