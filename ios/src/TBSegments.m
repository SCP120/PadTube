#import "TBSegments.h"
#import "TBStyle.h"

@implementation TBSegments {
    NSMutableArray *_buttons;
}
- (void)setTitles:(NSArray *)titles {
    _titles = titles;
    for (UIView *b in _buttons) [b removeFromSuperview];
    _buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = TBFont(15);
        b.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [b setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [_buttons addObject:b];
    }
    self.selected = _selected < (NSInteger)titles.count ? _selected : 0;
}
- (void)setSelected:(NSInteger)s {
    _selected = s;
    for (UIButton *b in _buttons) {
        BOOL on = b.tag == s;
        [b setBackgroundImage:[TBStyle segmentImage:on] forState:UIControlStateNormal];
        [b setTitleColor:on ? [UIColor whiteColor] : TBHex(0xBCBCBC) forState:UIControlStateNormal];
    }
}
- (void)tap:(UIButton *)b { self.selected = b.tag; if (self.changed) self.changed(b.tag); }
- (void)layoutSubviews {
    CGFloat w = self.bounds.size.width / MAX(1, _buttons.count);
    for (NSUInteger i = 0; i < _buttons.count; i++) [_buttons[i] setFrame:CGRectMake(floor(i * w), 0, ceil(w), self.bounds.size.height)];
}
@end

