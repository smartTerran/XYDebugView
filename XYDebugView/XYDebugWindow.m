//
//  XYDebugWindow.m
//  Pods
//
//  Created by XcodeYang on 25/05/2017.
//
//

#import "XYDebugWindow.h"
#import "XYDebugViewManager.h"
#import "XYDebugCategory.h"

#ifndef SCREEN_WIDTH
#define SCREEN_WIDTH    [UIScreen mainScreen].bounds.size.width
#endif

#ifndef SCREEN_HEIGHT
#define SCREEN_HEIGHT   [UIScreen mainScreen].bounds.size.height
#endif

@interface XYDebugWindow ()<UIGestureRecognizerDelegate>
{
	CGPoint _panPoint;
	CGPoint _doublePoint;
	CATransform3D _sublayerTransform;
}
@property (nonatomic, strong) DebugSlider *layerSlider;

@property (nonatomic, strong) DebugSlider *distanceSlider;

@property (nonatomic, strong) UIView *layerSourceView;

@property (nonatomic, strong) NSHashTable <CALayer *> *debugLayers;

@property (nonatomic, strong) NSMutableSet *doubleTouchsGestures;
@end

@implementation XYDebugWindow

#pragma mark - life cycle

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_doubleTouchsGestures = [NSMutableSet set];
		
		_statusBarButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_statusBarButton setTitle:@"tap statusbar to refresh debugging..." forState:UIControlStateNormal];
		_statusBarButton.backgroundColor = [UIColor redColor];
		_statusBarButton.titleLabel.font = [UIFont systemFontOfSize:11];
		_statusBarButton.layer.zPosition = MAXFLOAT;
		
		CGFloat width = CGRectGetWidth(self.frame);
		CGFloat height = CGRectGetHeight(self.frame);
		CGFloat length = MAX(width, height);
		_layerSourceView = [[UIView alloc] initWithFrame:CGRectMake((width-length)/2.0, (height-length)/2.0, length, length)];
		_layerSourceView.layer.zPosition = -MAXFLOAT;
		_layerSourceView.backgroundColor = [UIColor darkGrayColor];
		_layerSourceView.hidden = YES;
		_layerSourceView.multipleTouchEnabled = YES;
		
		_layerSlider = [[DebugSlider alloc] initWithFrame:CGRectMake(SCREEN_WIDTH-30, 40, 30, SCREEN_HEIGHT-40*2)];
		_layerSlider.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
		_layerSlider.hidden = YES;
		
		_distanceSlider = [[DebugSlider alloc] initWithFrame:CGRectMake(0, 40, 30, SCREEN_HEIGHT-40*2)];
		_distanceSlider.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
		_distanceSlider.hidden = YES;
		_distanceSlider.defalutPercent = 0.5;
		typeof(self) weakSelf = self;
		_layerSlider.touchMoveBlock = ^(float percent) {
			[weakSelf showDifferentLayers:percent];
		};
		_layerSlider.touchEndBlock = ^{
			weakSelf.layerSlider.defalutPercent = 0;
			[weakSelf showAllLayer];
		};
		_distanceSlider.touchMoveBlock = ^(float percent) {
			[weakSelf changeDistance:percent];
		};
		
		[self addSubview:_layerSourceView];
		[self addSubview:_statusBarButton];
		[self addSubview:_layerSlider];
		[self addSubview:_distanceSlider];
		self.backgroundColor = [UIColor clearColor];
		self.debugLayers = [NSHashTable weakObjectsHashTable];
		self.layer.masksToBounds = YES;
		
		UIPanGestureRecognizer *singlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(singlePan:)];
		
		UIPanGestureRecognizer *doublePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(doublePan:)];
		doublePan.minimumNumberOfTouches = 2;
		doublePan.delegate = self;
		doublePan.cancelsTouchesInView = NO;
		
		UIRotationGestureRecognizer *rotate = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotateGes:)];
		rotate.delegate = self;
		rotate.cancelsTouchesInView = NO;
		
		UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGes:)];
		pinch.delegate = self;
		pinch.cancelsTouchesInView = NO;
		
		[self.layerSourceView addGestureRecognizer:singlePan];
		[self.layerSourceView addGestureRecognizer:doublePan];
		[self.layerSourceView addGestureRecognizer:rotate];
		[self.layerSourceView addGestureRecognizer:pinch];
		
		self.layerSourceView.multipleTouchEnabled = YES;
		[_doubleTouchsGestures addObjectsFromArray:@[doublePan,rotate,pinch]];
	}
	return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	if (self.userInteractionEnabled==NO || self.hidden==YES || self.alpha<=0.01) {
		return nil;
	} else if (![self pointInside:point withEvent:event]) {
		return nil;
	} else if (_frameManager.isDebugging) {
		if (CGRectContainsPoint(_statusBarButton.frame,point)) {
			return _statusBarButton;
		} else if (CGRectContainsPoint(_layerSlider.frame,point) && _souceView) {
			return _layerSlider;
		} else if (CGRectContainsPoint(_distanceSlider.frame,point) && _souceView) {
			return _distanceSlider;
		} else if (CGRectContainsPoint(_layerSourceView.frame,point) && _souceView) {
			return _layerSourceView;
		}
	}
	return nil;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGFloat width = CGRectGetWidth(self.frame);
	CGFloat height = CGRectGetHeight(self.frame);
	CGFloat length = MAX(width, height);
	_layerSourceView.frame = CGRectMake((width-length)/2.0, (height-length)/2.0, length, length);
	
	_statusBarButton.frame = CGRectMake(0, 0, width, 20);
	
}

- (void)setSouceView:(UIView *)souceView
{
	_souceView = souceView;
	
	if (_souceView == nil) {
		_layerSourceView.hidden = YES;
		_layerSlider.hidden = YES;
		_distanceSlider.hidden = YES;
		
	} else {
		[[self.debugLayers allObjects] makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
		[self.debugLayers removeAllObjects];
		[self scrollViewAddLayersInView:_souceView layerLevel:0 index:0];
		_layerSourceView.hidden = NO;
		_layerSlider.hidden = NO;
		_distanceSlider.hidden = NO;
		[self reCalculateZPostion];
		[self recoverLayersDistance];
	}
}

#pragma mark - private

- (void)scrollViewAddLayersInView:(UIView *)view layerLevel:(CGFloat)layerLevel index:(NSUInteger)index
{
	if ([view isKindOfClass:[UIView class]] && view) {
		if (view.superview) {
			UIView *cloneView = view.debug_cloneView;
			cloneView.layer.zPosition = 0;
			cloneView.layer.debug_zPostion = layerLevel*20+index;
//			cloneView.layer.masksToBounds = YES;
			cloneView.layer.frame = [view.superview convertRect:view.frame toView:_souceView];
			cloneView.layer.opacity = 0.8;
			[self.debugLayers addObject:cloneView.layer];
			[self.layerSourceView.layer addSublayer:cloneView.layer];
		}
		[view.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			[self scrollViewAddLayersInView:obj layerLevel:layerLevel+1 index:idx];
		}];
	}
}

- (void)reCalculateZPostion
{
	CGFloat positionMax = self.debugLayers.anyObject.debug_zPostion;
	CGFloat positionMin = positionMax;
	for (CALayer *layer in self.debugLayers) {
		if (layer.debug_zPostion >= positionMax) {
			positionMax = layer.debug_zPostion;
		}
		if (layer.debug_zPostion <= positionMin) {
			positionMin = layer.debug_zPostion;
		}
	}
	
	CGFloat defalutMin = -600;
	CGFloat defalutMax = 400;
	CGFloat scale = (defalutMax-defalutMin)/(positionMax-positionMin);
	for (CALayer *layer in self.debugLayers) {
		layer.debug_zPostion = defalutMin + (layer.debug_zPostion - positionMin)*scale;
	}
}

#pragma mark - actions

- (void)showDifferentLayers:(float)percent
{
	CGFloat positionMax = self.debugLayers.anyObject.debug_zPostion;
	CGFloat positionMin = positionMax;
	for (CALayer *layer in self.debugLayers) {
		if (layer.debug_zPostion >= positionMax) {
			positionMax = layer.debug_zPostion;
		}
		if (layer.debug_zPostion <= positionMin) {
			positionMin = layer.debug_zPostion;
		}
	}
	// 分成20节,每节为5
	CGFloat gap = (positionMax - positionMin)/20.f;
	
	// 每节为5，计算当前处于那一节的layer层显示
	float num = ceil((percent * 100)/5.f);
	
	CGFloat upRange = positionMin + gap*num;
	CGFloat dowmRange = positionMin + gap*(num-1);
	
	for (CALayer *layer in self.debugLayers) {
		layer.opacity = (layer.debug_zPostion>upRange || layer.debug_zPostion<dowmRange) ? 0.1:1;
	}
}

- (void)showAllLayer
{
	for (CALayer *layer in self.debugLayers) {
		layer.opacity = 0.8;
	}
}

- (void)changeDistance:(float)percent
{
	for (CALayer *layer in self.debugLayers) {
		[layer removeAnimationForKey:@"zPosition"];
		CGFloat newZPostion = 2 * layer.debug_zPostion * percent;
		layer.zPosition = newZPostion;
	}
}

- (void)recoverLayersDistance
{
	_distanceSlider.defalutPercent = 0.5;
	// 向上平移100
	CATransform3D transform = CATransform3DScale(CATransform3DMakeTranslation(0, -100, 0), 0.6, 0.6, 0.6);
	transform.m34 = -1.0 / SCREEN_HEIGHT;
	_layerSourceView.layer.sublayerTransform = transform;
	
	for (CALayer *layer in self.debugLayers) {
		[layer debug_zPositionAnimationFrom:layer.zPosition to:layer.debug_zPostion duration:0.6];
	}
}

- (void)singlePan:(UIPanGestureRecognizer *)pan
{
	switch (pan.state) {
		case UIGestureRecognizerStateBegan: {
			_panPoint = [pan locationInView:_layerSourceView];
			_sublayerTransform = _layerSourceView.layer.sublayerTransform;
		}
			break;
		case UIGestureRecognizerStateChanged: {
			CGPoint current = [pan locationInView:_layerSourceView];
			CGFloat angleX = (current.x - _panPoint.x) * M_PI / SCREEN_WIDTH;
			CGFloat angleY = (current.y - _panPoint.y) * M_PI / SCREEN_HEIGHT;
			CATransform3D transform3D = CATransform3DRotate(_sublayerTransform, angleX, 0, 1, 0);
			_layerSourceView.layer.sublayerTransform = CATransform3DRotate(transform3D, -angleY, 1, 0, 0);
		}
			break;
		default:
			break;
	}
}

- (void)doublePan:(UIPanGestureRecognizer *)pan
{
	if (pan.numberOfTouches<=1) {
		return;
	}
	
	if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
		CGPoint point = [pan translationInView:_layerSourceView];
		_layerSourceView.layer.sublayerTransform = CATransform3DTranslate(_layerSourceView.layer.sublayerTransform, point.x, point.y, 0);
		[pan setTranslation:CGPointZero inView:_layerSourceView];
	}
}

- (void)rotateGes:(UIRotationGestureRecognizer *)rotate
{
	_layerSourceView.layer.sublayerTransform = CATransform3DRotate(_layerSourceView.layer.sublayerTransform, rotate.rotation, 0, 0, 1);
	[rotate setRotation:0];
}

- (void)pinchGes:(UIPinchGestureRecognizer *)pinch
{
	_layerSourceView.layer.sublayerTransform = CATransform3DScale(_layerSourceView.layer.sublayerTransform, pinch.scale, pinch.scale, pinch.scale);
	[pinch setScale:1];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if ([_doubleTouchsGestures containsObject:gestureRecognizer] && [_doubleTouchsGestures containsObject:otherGestureRecognizer]) {
		return YES;
	}
	return NO;
}

@end

