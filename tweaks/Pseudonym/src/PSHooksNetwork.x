#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#import "PSConfig.h"

// Routes an enabled app's traffic through an HTTP/HTTPS proxy.
//
// Scope is worth being precise about: this sets connectionProxyDictionary on the
// session configurations apps get from NSURLSession, which covers the great
// majority of modern networking. It does NOT cover an app that opens raw BSD
// sockets or ships its own TLS stack (cronet, BoringSSL and similar), and iOS
// does not honour SOCKS through connectionProxyDictionary at all - hence
// HTTP/HTTPS only.
static BOOL PSProxyActive(void) {
    return PSConfigActive()
        && PSConfigProxyEnabled()
        && PSConfigProxyHost().length
        && PSConfigProxyPort() > 0;
}

static NSDictionary *PSProxyDictionary(void) {
    NSString *host = PSConfigProxyHost();
    NSNumber *port = @(PSConfigProxyPort());
    NSMutableDictionary *proxy = [NSMutableDictionary dictionary];

    proxy[(NSString *)kCFNetworkProxiesHTTPEnable] = @YES;
    proxy[(NSString *)kCFNetworkProxiesHTTPProxy] = host;
    proxy[(NSString *)kCFNetworkProxiesHTTPPort] = port;

    // The HTTPS counterparts of those constants are macOS-only. On iOS the bare
    // string keys are what CFNetwork actually reads, so spelling them out is the
    // only way to proxy TLS traffic here.
    proxy[@"HTTPSEnable"] = @YES;
    proxy[@"HTTPSProxy"] = host;
    proxy[@"HTTPSPort"] = port;

    NSString *user = PSConfigProxyUser();
    if (user.length) {
        proxy[(NSString *)kCFProxyUsernameKey] = user;
        NSString *password = PSConfigProxyPassword();
        if (password.length) {
            proxy[(NSString *)kCFProxyPasswordKey] = password;
        }
    }
    return proxy;
}

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    if (PSProxyActive()) {
        config.connectionProxyDictionary = PSProxyDictionary();
    }
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    if (PSProxyActive()) {
        config.connectionProxyDictionary = PSProxyDictionary();
    }
    return config;
}

+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier {
    NSURLSessionConfiguration *config = %orig;
    if (PSProxyActive()) {
        config.connectionProxyDictionary = PSProxyDictionary();
    }
    return config;
}

%end
