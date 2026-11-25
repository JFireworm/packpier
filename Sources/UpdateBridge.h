// Public Sparkle 2.9.6 selectors and error codes used by Packpier. The distribution omits headers.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const SUSparkleErrorDomain;
enum {
    SUNoUpdateError = 1001,
    SUInstallationCanceledError = 4007,
    SUInstallationAuthorizeLaterError = 4008
};

@class SPUUpdater;
NS_SWIFT_UI_ACTOR @protocol SPUUpdaterDelegate <NSObject>
@optional
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error;
@end

@interface SPUUpdater : NSObject
@property (nonatomic) BOOL automaticallyChecksForUpdates;
@property (nonatomic) BOOL automaticallyDownloadsUpdates;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (BOOL)startUpdater:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(start());
- (void)checkForUpdates;
@end
@interface SPUStandardUpdaterController : NSObject
@property (nonatomic, readonly) SPUUpdater *updater;
- (instancetype)initWithStartingUpdater:(BOOL)start updaterDelegate:(nullable id<SPUUpdaterDelegate>)delegate userDriverDelegate:(nullable id)driver NS_SWIFT_NAME(init(starting:delegate:driver:));
@end
NS_ASSUME_NONNULL_END
