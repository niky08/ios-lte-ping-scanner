#import "SimplePing.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>

static const uint16_t kICMPTypeEchoRequest = 8;
static const uint16_t kICMPTypeEchoReply = 0;

@interface SimplePing ()
@property (nonatomic, copy, readwrite) NSString *hostName;
@property (nonatomic, strong, nullable) NSData *hostAddress;
@property (nonatomic, assign) int socketFD;
@property (nonatomic, assign) uint16_t sequenceNumber;
@property (nonatomic, assign) uint16_t identifier;
@property (nonatomic, strong, nullable) NSTimer *timeoutTimer;
@end

@implementation SimplePing

+ (instancetype)pingWithHostName:(NSString *)hostName {
    SimplePing *obj = [[SimplePing alloc] init];
    obj->_hostName = [hostName copy];
    obj->_ttl = 64;
    obj->_payloadSize = 56;
    obj->_identifier = (uint16_t)arc4random();
    obj->_socketFD = -1;
    return obj;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    struct addrinfo *res = NULL;
    int err = getaddrinfo(self.hostName.UTF8String, NULL, &hints, &res);
    if (err != 0 || res == NULL) {
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:@{NSLocalizedDescriptionKey: @"DNS resolve failed"}];
        [self notifyFailure:error];
        return;
    }

    for (struct addrinfo *ai = res; ai != NULL; ai = ai->ai_next) {
        if (ai->ai_family == AF_INET) {
            self.hostAddress = [NSData dataWithBytes:ai->ai_addr length:ai->ai_addrlen];
            break;
        }
    }
    freeaddrinfo(res);

    if (self.hostAddress == nil) {
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:@{NSLocalizedDescriptionKey: @"No IPv4 address"}];
        [self notifyFailure:error];
        return;
    }

    self.socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (self.socketFD < 0) {
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: @"ICMP socket failed"}];
        [self notifyFailure:error];
        return;
    }

    int ttl = (int)self.ttl;
    setsockopt(self.socketFD, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl));

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self readLoop];
    });

    [self notifyStart];
}

- (void)notifyStart {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(simplePing:didStartWithAddress:)]) {
            [self.delegate simplePing:self didStartWithAddress:self.hostAddress];
        }
    });
}

- (void)notifyFailure:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(simplePing:didFailWithError:)]) {
            [self.delegate simplePing:self didFailWithError:error];
        }
    });
}

- (void)stop {
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
    if (self.socketFD >= 0) {
        close(self.socketFD);
        self.socketFD = -1;
    }
}

- (NSData *)buildPacketWithSequence:(uint16_t)sequenceNumber {
    NSMutableData *payload = [NSMutableData dataWithLength:self.payloadSize];
    NSMutableData *packet = [NSMutableData dataWithLength:sizeof(struct icmp) + payload.length];

    struct icmp *icmpPtr = packet.mutableBytes;
    icmpPtr->icmp_type = kICMPTypeEchoRequest;
    icmpPtr->icmp_code = 0;
    icmpPtr->icmp_cksum = 0;
    icmpPtr->icmp_id = htons(self.identifier);
    icmpPtr->icmp_seq = htons(sequenceNumber);
    memcpy(icmpPtr + 1, payload.bytes, payload.length);

    uint16_t checksum = in_cksum(packet.bytes, (int)packet.length);
    icmpPtr->icmp_cksum = checksum;
    return packet;
}

static uint16_t in_cksum(const void *buffer, int length) {
    const uint16_t *addr = buffer;
    int nleft = length;
    uint32_t sum = 0;
    while (nleft > 1) {
        sum += *addr++;
        nleft -= 2;
    }
    if (nleft == 1) {
        sum += *(const uint8_t *)addr;
    }
    sum = (sum >> 16) + (sum & 0xffff);
    sum += (sum >> 16);
    return (uint16_t)~sum;
}

- (void)sendPing {
    if (self.socketFD < 0 || self.hostAddress == nil) { return; }

    self.sequenceNumber += 1;
    NSData *packet = [self buildPacketWithSequence:self.sequenceNumber];

    const struct sockaddr *addr = self.hostAddress.bytes;
    ssize_t sent = sendto(self.socketFD, packet.bytes, packet.length, 0, addr, (socklen_t)self.hostAddress.length);
    if (sent < 0) {
        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        if ([self.delegate respondsToSelector:@selector(simplePing:didFailToSendPacket:sequenceNumber:error:)]) {
            [self.delegate simplePing:self didFailToSendPacket:packet sequenceNumber:self.sequenceNumber error:error];
        }
        return;
    }

    if ([self.delegate respondsToSelector:@selector(simplePing:didSendPacket:sequenceNumber:)]) {
        [self.delegate simplePing:self didSendPacket:packet sequenceNumber:self.sequenceNumber];
    }
}

- (void)readLoop {
    uint8_t buffer[65535];
    while (self.socketFD >= 0) {
        struct sockaddr_storage fromAddr;
        socklen_t fromLen = sizeof(fromAddr);
        ssize_t bytesRead = recvfrom(self.socketFD, buffer, sizeof(buffer), 0, (struct sockaddr *)&fromAddr, &fromLen);
        if (bytesRead < 0) {
            if (errno == EINTR) { continue; }
            break;
        }
        if (bytesRead < (ssize_t)(sizeof(struct ip) + sizeof(struct icmp))) { continue; }

        const struct ip *ipPtr = (const struct ip *)buffer;
        int ipHeaderLength = ipPtr->ip_hl * 4;
        if (bytesRead < ipHeaderLength + (ssize_t)sizeof(struct icmp)) { continue; }

        const struct icmp *icmpPtr = (const struct icmp *)(buffer + ipHeaderLength);
        if (icmpPtr->icmp_type != kICMPTypeEchoReply) { continue; }
        if (ntohs(icmpPtr->icmp_id) != self.identifier) { continue; }

        uint16_t seq = ntohs(icmpPtr->icmp_seq);
        NSData *packet = [NSData dataWithBytes:icmpPtr length:sizeof(struct icmp)];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(simplePing:didReceivePingResponsePacket:sequenceNumber:)]) {
                [self.delegate simplePing:self didReceivePingResponsePacket:packet sequenceNumber:seq];
            }
        });
    }
}

@end