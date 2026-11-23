// Public Sparkle 2 selectors used by Packpier. The runtime-only macOS distribution omits headers.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SPUUpdater : NSObject
@property (nonatomic) BOOL automaticallyChecksForUpdates;
@property (nonatomic) BOOL automaticallyDownloadsUpdates;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (BOOL)startUpdater:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(start());
- (void)checkForUpdates;
@end
@interface SPUStandardUpdaterController : NSObject
@property (nonatomic, readonly) SPUUpdater *updater;
- (instancetype)initWithStartingUpdater:(BOOL)start updaterDelegate:(nullable id)delegate userDriverDelegate:(nullable id)driver NS_SWIFT_NAME(init(starting:delegate:driver:));
@end
NS_ASSUME_NONNULL_END
