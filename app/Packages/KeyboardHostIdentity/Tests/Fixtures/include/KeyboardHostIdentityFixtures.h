#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface NibbleIdentityTestProxy : NSObject <UITextDocumentProxy>
@property (nonatomic, readonly) NSUInteger documentReadCount;
@property (nonatomic, readonly) NSUInteger contextReadCount;
@property (nonatomic, readonly) NSUInteger unexpectedMutationCount;
@property (nonatomic, readonly, copy) NSArray<NSString *> *insertedTexts;
@end

NS_SWIFT_UI_ACTOR
@interface NibbleIdentityTestController : UIInputViewController
- (instancetype)initWithDocument:(NSUUID * _Nullable)document;
@property (nonatomic, readonly, strong) NibbleIdentityTestProxy *fixtureProxy;
@property (nonatomic) BOOL proxyUnavailable;
@property (nonatomic) BOOL admissionAllowed;
@property (nonatomic) BOOL invalidatesAdmissionDuringDocumentRead;
@property (nonatomic, readonly) NSUInteger admissionInvalidationCount;
@end

NS_ASSUME_NONNULL_END
