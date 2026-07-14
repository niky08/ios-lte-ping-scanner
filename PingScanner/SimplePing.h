#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SimplePingDelegate <NSObject>
@optional
- (void)simplePing:(id)pinger didStartWithAddress:(NSData *)address;
- (void)simplePing:(id)pinger didFailWithError:(NSError *)error;
- (void)simplePing:(id)pinger didSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber;
- (void)simplePing:(id)pinger didFailToSendPacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber error:(NSError *)error;
- (void)simplePing:(id)pinger didReceivePingResponsePacket:(NSData *)packet sequenceNumber:(uint16_t)sequenceNumber;
- (void)simplePing:(id)pinger didReceiveUnexpectedPacket:(NSData *)packet;
@end

@interface SimplePing : NSObject

@property (nonatomic, copy, readonly) NSString *hostName;
@property (nonatomic, weak, nullable) id<SimplePingDelegate> delegate;
@property (nonatomic, assign) NSUInteger ttl;
@property (nonatomic, assign) NSUInteger payloadSize;

+ (instancetype)pingWithHostName:(NSString *)hostName NS_SWIFT_NAME(init(hostName:));
- (void)start;
- (void)stop;
- (void)sendPing NS_SWIFT_NAME(send());

@end

NS_ASSUME_NONNULL_END