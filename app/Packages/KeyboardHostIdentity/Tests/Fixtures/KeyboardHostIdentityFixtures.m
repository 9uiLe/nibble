#import "KeyboardHostIdentityFixtures.h"

@interface NibbleIdentityTestAdmission : NSObject
@property (nonatomic) BOOL allowed;
@property (nonatomic) NSUInteger invalidationCount;
@end

@implementation NibbleIdentityTestAdmission
@end

@interface NibbleIdentityTestProxy ()
@property (nonatomic, nullable, copy) NSUUID *suppliedDocument;
@property (nonatomic, nullable, copy) void (^didReadDocument)(void);
@property (nonatomic, readwrite) NSUInteger documentReadCount;
@property (nonatomic, readwrite) NSUInteger contextReadCount;
@property (nonatomic, readwrite) NSUInteger unexpectedMutationCount;
@property (nonatomic, strong) NSMutableArray<NSString *> *insertions;
@end

@implementation NibbleIdentityTestProxy

- (instancetype)init {
    self = [super init];
    if (self) {
        _insertions = [NSMutableArray new];
    }
    return self;
}

// These fixtures reproduce UIKit's observed runtime violation of its nonnull contract.
// Swift must only receive the value through the nullable production wrapper.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"
- (NSUUID *)documentIdentifier {
    self.documentReadCount += 1;
    if (self.didReadDocument) {
        self.didReadDocument();
    }
    return self.suppliedDocument;
}
#pragma clang diagnostic pop

- (NSString *)documentContextBeforeInput {
    self.contextReadCount += 1;
    return @"context must not be requested";
}

- (NSString *)documentContextAfterInput {
    self.contextReadCount += 1;
    return @"context must not be requested";
}

- (NSString *)selectedText {
    self.contextReadCount += 1;
    return @"selection text must not be requested";
}

- (UITextInputMode *)documentInputMode {
    return nil;
}

- (BOOL)hasText {
    return NO;
}

- (void)insertText:(NSString *)text {
    [self.insertions addObject:[text copy]];
}

- (NSArray<NSString *> *)insertedTexts {
    return [self.insertions copy];
}

- (void)deleteBackward {
    self.unexpectedMutationCount += 1;
}

- (void)adjustTextPositionByCharacterOffset:(NSInteger)offset {
    self.unexpectedMutationCount += 1;
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    self.unexpectedMutationCount += 1;
}

- (void)unmarkText {
    self.unexpectedMutationCount += 1;
}

@end

@interface NibbleIdentityTestController ()
@property (nonatomic, readwrite, strong) NibbleIdentityTestProxy *fixtureProxy;
@property (nonatomic, strong) NibbleIdentityTestAdmission *admission;
@end

@implementation NibbleIdentityTestController

- (instancetype)initWithDocument:(NSUUID *)document {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _fixtureProxy = [NibbleIdentityTestProxy new];
        _fixtureProxy.suppliedDocument = document;
        _admission = [NibbleIdentityTestAdmission new];
        _admission.allowed = YES;
    }
    return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"
- (id<UITextDocumentProxy>)textDocumentProxy {
    id<UITextDocumentProxy> _Nullable result = self.proxyUnavailable ? nil : self.fixtureProxy;
    return result;
}
#pragma clang diagnostic pop

- (BOOL)admissionAllowed {
    return self.admission.allowed;
}

- (void)setAdmissionAllowed:(BOOL)allowed {
    self.admission.allowed = allowed;
}

- (NSUInteger)admissionInvalidationCount {
    return self.admission.invalidationCount;
}

- (void)setInvalidatesAdmissionDuringDocumentRead:(BOOL)invalidates {
    _invalidatesAdmissionDuringDocumentRead = invalidates;
    if (!invalidates) {
        self.fixtureProxy.didReadDocument = nil;
        return;
    }
    NibbleIdentityTestAdmission *admission = self.admission;
    // Capture the independent state, not the controller or proxy, to avoid a cycle.
    self.fixtureProxy.didReadDocument = ^{
        admission.allowed = NO;
        admission.invalidationCount += 1;
    };
}

@end
