//
//  PlayerView.m
//  VideoPlayer3
//
//  Created by 焦英博 on 16/9/17.
//  Copyright © 2016年 焦英博. All rights reserved.
//

#import "PlayerView.h"
#import "YBPlayerToolView.h"

typedef struct {
    unsigned int didClickFullScreenButton : 1;
} DelegateFlags; //记录delegate响应了哪些方法，这里只有一个代理方法

@interface PlayerView ()

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityView;
@property (nonatomic, strong) YBPlayerToolView *toolView;

@property (nonatomic, copy) NSString *urlString; //网络视频地址
@property (nonatomic, copy) NSString *pathString; //本地视频地址
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;

@property (nonatomic, assign) BOOL paused; //记录暂停状态
@property (nonatomic, strong) id playbackObserver;
@property (nonatomic, assign) DelegateFlags delegateFlags;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign, readwrite) BOOL playEnded; //是否播放完毕
@property (nonatomic, assign, readwrite) BOOL fullScreen; //是否是全屏
@property (nonatomic, assign) CGRect toolFrame;

// 记录小屏时的parentView
@property (nonatomic, weak) UIView *movieViewParentView;
// 记录小屏时的frame
@property (nonatomic, assign) CGRect movieViewFrame;
@property (nonatomic, assign) MovieViewState state;

@end

@implementation PlayerView

#pragma mark - 初始化方法
+ (instancetype)viewWithFrame:(CGRect)frame {
    PlayerView *view = [PlayerView pv_instanceView];
    view.frame = frame;
    return view;
}

#pragma mark - 系统方法
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        
    }
    return self;
}

//- (instancetype)init {
//    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"必须使用 viewWithFrame: 方法初始化" userInfo:nil];
//}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    [self.imageView.layer addSublayer:self.playerLayer];
    [self pv_resetUI];
    self.fullScreen = NO;
    self.paused = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pv_applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    
    self.toolView = [YBPlayerToolView instanceView];
    self.toolFrame = CGRectMake(0, self.bounds.size.height-50, self.bounds.size.width, 50);
    self.toolView.frame = self.toolFrame;
    self.toolView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:self.toolView];
    [self.toolView.playButton addTarget:self action:@selector(pv_playButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.toolView.slider addTarget:self action:@selector(pv_sliderTouchBegin:) forControlEvents:UIControlEventTouchDown];
    [self.toolView.slider addTarget:self action:@selector(pv_sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.toolView.slider addTarget:self action:@selector(pv_sliderTouchEnd:) forControlEvents:UIControlEventTouchUpInside];
    [self.toolView.fullButton addTarget:self action:@selector(pv_fullScreenBtnClick:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.playerLayer.frame = self.bounds;
}

- (void)dealloc {
    [self.player removeTimeObserver:self.playbackObserver];
    [self pv_playerItemRemoveObserver];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerStatus status= [[change objectForKey:@"new"] intValue];
        if (status == AVPlayerStatusReadyToPlay) {
            [self.activityView stopAnimating];
            [self pv_setTimeLabel];
            // 开始自动播放
            self.toolView.playButton.enabled = YES;
            self.toolView.slider.enabled = YES;
            [self pv_playButtonClick:self.toolView.playButton];
        }
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        NSArray *array = self.player.currentItem.loadedTimeRanges;
        CMTimeRange timeRange = [array.firstObject CMTimeRangeValue];//本次缓冲时间范围
        NSTimeInterval startSeconds = CMTimeGetSeconds(timeRange.start);//本次缓冲起始时间
        NSTimeInterval durationSeconds = CMTimeGetSeconds(timeRange.duration);//缓冲时间
        NSTimeInterval totalBuffer = startSeconds + durationSeconds;//缓冲总长度
        float totalTime = CMTimeGetSeconds(self.player.currentItem.duration);//视频总长度
        float progress = totalBuffer/totalTime;//缓冲进度
        [self.toolView.progressView setProgress:progress];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.toolView.hidden == YES) {
        [self pv_showToolView];
    } else {
        [self pv_hideToolView];
    }
}

#pragma mark - public method

- (void)playWithRemoteURL:(NSString *)url {
    self.urlString = url;
}

- (void)playWithLocalURL:(NSString *)url {
    self.pathString = url;
}

#pragma mark - setter

- (void)setUrlString:(NSString *)urlString {
    _urlString = urlString;
    [self pv_resetPlayer];
    if (self.player.currentItem != nil) {
        [self pv_playerItemRemoveNotification];
        [self pv_playerItemRemoveObserver];
    }
    AVPlayerItem *playerItem = [self pv_getPlayerItemWithURLString:urlString];
    [self pv_addObserverToPlayerItem:playerItem];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        [self pv_playerItemAddNotification];
    });
}

- (void)setPathString:(NSString *)pathString {
    _pathString = pathString;
    [self pv_resetPlayer];
    if (self.player.currentItem != nil) {
        [self pv_playerItemRemoveNotification];
        [self pv_playerItemRemoveObserver];
    }
    AVPlayerItem *playerItem = [self pv_getPlayerItemWithPath:pathString];
    [self pv_addObserverToPlayerItem:playerItem];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        [self pv_playerItemAddNotification];
    });
}

- (void)setDelegate:(id<PlayerViewDelegate>)delegate {
    _delegate = delegate;
    if ([delegate respondsToSelector:@selector(playerViewDidClickFullScreenButton:)]) {
        _delegateFlags.didClickFullScreenButton = [delegate respondsToSelector:@selector(playerViewDidClickFullScreenButton:)];
    }
}

#pragma mark - getter
- (AVPlayer *)player {
    if (!_player) {
        _player = [[AVPlayer alloc] init];
        __weak typeof(self) weakSelf = self;
        // 播放1s回调一次
        self.playbackObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:NULL usingBlock:^(CMTime time) {
            [weakSelf pv_setTimeLabel];
            NSTimeInterval totalTime = CMTimeGetSeconds(weakSelf.player.currentItem.duration);
            weakSelf.toolView.slider.value = time.value/time.timescale/totalTime;//time.value/time.timescale是当前时间
        }];
    }
    return _player;
}

- (AVPlayerLayer *)playerLayer {
    if (!_playerLayer) {
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    }
    return _playerLayer;
}

#pragma mark -
#pragma mark - 私有方法
+ (instancetype)pv_instanceView {
    return [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(self) owner:nil options:nil] firstObject];
}

- (void)pv_resetUI {
    [self.toolView.slider setThumbImage:[UIImage imageNamed:@"point"] forState:UIControlStateNormal];
    [self.toolView.slider setMaximumTrackImage:[self pv_imageWithColor:[UIColor clearColor] size:CGSizeMake(300, 2)] forState:UIControlStateNormal];
    [self.toolView.progressView setProgressTintColor:[UIColor colorWithRed:135/255.0 green:206/255.0 blue:235/255.0 alpha:.8]];
    [self.toolView.progressView setTrackTintColor:[UIColor whiteColor]];
}

- (AVPlayerItem *)pv_getPlayerItemWithURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    return item;
}

- (AVPlayerItem *)pv_getPlayerItemWithPath:(NSString *)pathString {
    NSURL *sourceMovieUrl = [NSURL fileURLWithPath:pathString];
    AVAsset *movieAsset = [AVURLAsset URLAssetWithURL:sourceMovieUrl options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:movieAsset];
    return item;
}

#pragma mark - 观察者
- (void)pv_playerItemAddNotification {
    // 播放完成通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pv_playbackFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
}

- (void)pv_addObserverToPlayerItem:(AVPlayerItem *)playerItem {
    // 监听播放状态
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    // 监听缓冲进度
    [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)pv_playerItemRemoveNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
}

- (void)pv_playerItemRemoveObserver {
    [self.player.currentItem removeObserver:self forKeyPath:@"status"];
    [self.player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
}

-(void)pv_playbackFinished:(NSNotification *)noti {
    self.playEnded = YES;
    if (self.toolView.playButton.selected) {
        self.toolView.playButton.selected = NO;
    }
}

- (void)pv_applicationWillResignActive:(NSNotification *)noti {
    if (self.player.rate == 1) {
        [self pv_playButtonClick:self.toolView.playButton];
    }
}

#pragma mark - 点击/滑动动作
- (void)pv_playButtonClick:(UIButton *)sender {
    if (self.player.rate == 0) {
        sender.selected = YES;
        self.paused = NO;
        [self pv_play];
    } else if (self.player.rate == 1) {
        sender.selected = NO;
        self.paused = YES;
        [self pv_pause];
    }
}

- (IBAction)pv_sliderTouchBegin:(UISlider *)sender {
    [self pv_pause];
}

- (IBAction)pv_sliderValueChanged:(UISlider *)sender {
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentItem.duration) * self.toolView.slider.value;
    NSInteger currentMin = currentTime / 60;
    NSInteger currentSec = (NSInteger)currentTime % 60;
    self.toolView.currentTime.text = [NSString stringWithFormat:@"%02td:%02td",currentMin,currentSec];
}

- (IBAction)pv_sliderTouchEnd:(UISlider *)sender {
    NSTimeInterval slideTime = CMTimeGetSeconds(self.player.currentItem.duration) * self.toolView.slider.value;
    if (slideTime == CMTimeGetSeconds(self.player.currentItem.duration)) {
        slideTime -= 0.5;
    }
    [self.player seekToTime:CMTimeMakeWithSeconds(slideTime, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    if (self.paused==NO && self.playEnded==NO) {
        [self pv_play];
    }
}

- (IBAction)pv_fullScreenBtnClick:(UIButton *)sender {
//    if (_delegateFlags.didClickFullScreenButton) {
//        [self.delegate playerViewDidClickFullScreenButton:self];
//        sender.selected = !sender.selected;
//    }
//    self.fullScreen = !self.fullScreen;
    
    if (self.state == MovieViewStateSmall) {
        [self enterFullscreen];
    } else if (self.state == MovieViewStateFullscreen) {
        [self exitFullscreen];
    }
    sender.selected = !sender.selected;
}

#pragma mark - 全屏

- (void)enterFullscreen {
    
    if (self.state != MovieViewStateSmall) {
        return;
    }
    
    self.state = MovieViewStateAnimating;
    
    // 记录进入全屏前的parentView和frame
    self.movieViewParentView = self.superview;
    self.movieViewFrame = self.frame;
    
    // movieView移到window上
    CGRect rectInWindow = [self convertRect:self.bounds toView:[UIApplication sharedApplication].keyWindow];
    [self removeFromSuperview];
    self.frame = rectInWindow;
    [[UIApplication sharedApplication].keyWindow addSubview:self];
    
    // 执行动画
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformMakeRotation(M_PI_2);
        self.bounds = CGRectMake(0, 0, CGRectGetHeight(self.superview.bounds), CGRectGetWidth(self.superview.bounds));
        self.center = CGPointMake(CGRectGetMidX(self.superview.bounds), CGRectGetMidY(self.superview.bounds));
        self.toolView.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.width-50, [UIScreen mainScreen].bounds.size.height, 50);
    } completion:^(BOOL finished) {
        self.state = MovieViewStateFullscreen;
    }];
    
    [self refreshStatusBarOrientation:UIInterfaceOrientationLandscapeRight];
}

- (void)exitFullscreen {
    
    if (self.state != MovieViewStateFullscreen) {
        return;
    }
    
    self.state = MovieViewStateAnimating;
    
    CGRect frame = [self.movieViewParentView convertRect:self.movieViewFrame toView:[UIApplication sharedApplication].keyWindow];
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformIdentity;
        self.frame = frame;
        self.toolView.frame = self.toolFrame;
    } completion:^(BOOL finished) {
        /*
         * movieView回到小屏位置
         */
        [self removeFromSuperview];
        self.frame = self.movieViewFrame;
        [self.movieViewParentView addSubview:self];
        self.state = MovieViewStateSmall;
    }];
    
    [self refreshStatusBarOrientation:UIInterfaceOrientationPortrait];
}

- (void)refreshStatusBarOrientation:(UIInterfaceOrientation)interfaceOrientation {
    [[UIApplication sharedApplication] setStatusBarOrientation:interfaceOrientation animated:YES];
}

#pragma mark - Time Label
- (void)pv_setTimeLabel {
    NSTimeInterval totalTime = CMTimeGetSeconds(self.player.currentItem.duration);
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentTime);
    // 切换视频源时totalTime/currentTime的值会出现nan导致时间错乱
    if (!(totalTime>=0)||!(currentTime>=0)) {
        totalTime = 0;
        currentTime = 0;
    }
    
    NSInteger totalMin = totalTime / 60;
    NSInteger totalSec = (NSInteger)totalTime % 60;
    self.toolView.totalTime.text = [NSString stringWithFormat:@"%02td:%02td",totalMin,totalSec];
    
    NSInteger currentMin = currentTime / 60;
    NSInteger currentSec = (NSInteger)currentTime % 60;
    self.toolView.currentTime.text = [NSString stringWithFormat:@"%02td:%02td",currentMin,currentSec];
}

#pragma mark - 播放状态
- (void)pv_play {
    // 如果已播放完毕，则重新从头开始播放
    if (self.playEnded == YES) {
        [self.player seekToTime:CMTimeMakeWithSeconds(0, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        self.playEnded = NO;
    }
    [self.player play];
}

- (void)pv_pause {
    [self.player pause];
}

- (void)pv_resetPlayer {
    self.playEnded = NO;
    self.paused = NO;
    [self pv_pause];
    if (self.toolView.playButton.selected) {
        self.toolView.playButton.selected = NO;
    }
    [self.activityView startAnimating];
}

#pragma mark - ToolView
- (void)pv_hideToolView {
    self.toolView.hidden = YES;
}

- (void)pv_showToolView {
    self.toolView.hidden = NO;
}

#pragma mark - 绘制图片
- (UIImage *)pv_imageWithColor:(UIColor *)color size:(CGSize)size {
    @autoreleasepool {
        CGRect rect = CGRectMake(0, 0, size.width, size.height);
        UIGraphicsBeginImageContext(rect.size);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillRect(ctx, rect);
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return image;
    }
}

@end
