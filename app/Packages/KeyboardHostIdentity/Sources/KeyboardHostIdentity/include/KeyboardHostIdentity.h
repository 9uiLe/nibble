#import <UIKit/UIKit.h>

NSUUID * _Nullable NibbleKeyboardDocumentIdentifier(UIInputViewController * _Nonnull controller) NS_SWIFT_UI_ACTOR;
BOOL NibbleKeyboardInsertText(UIInputViewController * _Nonnull controller,
                             NSString * _Nonnull text,
                             NSUUID * _Nonnull expectedDocument,
                             BOOL (NS_NOESCAPE ^ _Nonnull admission)(void)) NS_SWIFT_UI_ACTOR;
