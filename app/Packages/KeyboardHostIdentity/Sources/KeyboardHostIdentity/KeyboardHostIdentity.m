#import "KeyboardHostIdentity.h"

NSUUID * _Nullable NibbleKeyboardDocumentIdentifier(UIInputViewController *controller) {
    // iOS can return nil during host transitions despite the SDK's nonnull declaration.
    // Keep this public getter in Objective-C so Swift receives the actual optional value.
    return controller.textDocumentProxy.documentIdentifier;
}

BOOL NibbleKeyboardInsertText(UIInputViewController *controller, NSString *text,
                             NSUUID *expectedDocument, BOOL (^admission)(void)) {
    id<UITextDocumentProxy> proxy = controller.textDocumentProxy;
    if (proxy == nil || ![proxy.documentIdentifier isEqual:expectedDocument] || !admission()) {
        return NO;
    }
    [proxy insertText:text];
    return YES;
}
