#import <UIKit/UIKit.h>

/* The look of YouTube for iPad 1.x (2012), measured in docs/design/old-youtube-ui.md: dark gradient header and
 * guide, light grey content with paper cards, red progress bar. Every gradient and frame is drawn once into a
 * stretchable image (no layer shadows, masks or corner radii at run time: 55 fps gate). Icons are our own drawings. */

UIColor *TBHex(unsigned rgb);
UIFont *TBFont(CGFloat size);        /* HelveticaNeue */
UIFont *TBFontBold(CGFloat size);    /* HelveticaNeue-Bold */

extern NSString *const TBThemeChanged;  /* posted after +setDark: changed the theme */

/* Light / Dark (design §14, DUC-SET-THEME): colours and drawn images below follow the saved theme. */
@interface TBStyle : NSObject
+ (BOOL)dark;
+ (void)setDark:(BOOL)dark;          /* saves TBDark, clears the image cache, posts TBThemeChanged */
+ (UIColor *)contentBackground;      /* #E6E6E6 / #1B1B1B */
+ (UIColor *)cardFill;               /* #F5F5F5 / #2A2A2A */
+ (UIColor *)text;                   /* #333333 / #E4E4E4 */
+ (UIColor *)secondary;              /* #666666 / #A8A8A8 */
+ (UIColor *)tertiary;               /* #999999 / #7E7E7E */
+ (UIColor *)placeholder;            /* empty thumbnail or avatar */
+ (UIColor *)rule;                   /* line under a row */
+ (UIColor *)ruleLight;              /* the 1 px highlight under that line */
+ (UIColor *)buttonText;             /* text on +lightButtonImage */
+ (UIColor *)relatedFill;            /* related card on the dark panel */
+ (UIColor *)relatedTitle;
+ (UIColor *)relatedMeta;
+ (UIColor *)popupFill;              /* search suggestions list */
+ (UIColor *)popupRule;
+ (UIColor *)panel;                  /* #363636 / #232323 related panel */
+ (UIColor *)guideRow;               /* #383838 */
+ (UIColor *)guideText;              /* #AAAAAA */
+ (UIColor *)link;                   /* #3361CC / #7FA7F2 */
+ (UIImage *)headerImage;            /* 44 pt dark bar, stretchable */
+ (UIImage *)guideHeaderImage;
+ (UIImage *)sectionImage;           /* 22 pt guide section header */
+ (UIImage *)cardImage;              /* paper card with its edge lines, stretchable */
+ (UIImage *)smallCardImage;         /* related card */
+ (UIImage *)searchFieldImage;       /* dark pill */
+ (UIImage *)lightButtonImage:(BOOL)pressed;
+ (UIImage *)tabBarImage;            /* About / Comments bar */
+ (UIImage *)segmentImage:(BOOL)selected;
+ (UIImage *)controlBarImage;        /* player control bar */
+ (UIImage *)trackImage:(int)kind;   /* 0 played (red), 1 buffered, 2 unplayed */
+ (UIImage *)knobImage;
+ (UIImage *)badgeImage;             /* guide count badge */
/* Icons: menu, back, search, home, subs, history, later, playlist, like, liked, dislike, star, gear, account,
 * play, pause, replay, full, check, plus. tint: icon colour. */
+ (UIImage *)icon:(NSString *)name size:(CGFloat)size color:(UIColor *)tint;
+ (void)styleShadowLabel:(UILabel *)l; /* 1 px black shadow above, for text on dark areas */
@end
