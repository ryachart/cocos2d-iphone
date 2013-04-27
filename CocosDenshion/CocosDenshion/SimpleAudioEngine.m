/*
 Copyright (c) 2010 Steve Oldmeadow

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 $Id$
 */

#import "SimpleAudioEngine.h"

@interface SimpleAudioEngine ()
@property (nonatomic, readwrite) BOOL isCrossfading;
@property (nonatomic, readwrite) NSTimeInterval crossFadeDuration;
@property (nonatomic, readwrite) NSTimeInterval crossFadeProgress;
@property (nonatomic, readwrite) NSString *crossFadeTargetTrackFilePath;
@property (nonatomic, readwrite) float cachedBackgroundVolume;
@end

@implementation SimpleAudioEngine

static SimpleAudioEngine *sharedEngine = nil;
static CDSoundEngine* soundEngine = nil;
static CDAudioManager *am = nil;
static CDBufferManager *bufferManager = nil;

// Init
+ (SimpleAudioEngine *) sharedEngine
{
	@synchronized(self)     {
		if (!sharedEngine)
			sharedEngine = [[SimpleAudioEngine alloc] init];
	}
	return sharedEngine;
}

+ (id) alloc
{
	@synchronized(self)     {
		NSAssert(sharedEngine == nil, @"Attempted to allocate a second instance of a singleton.");
		return [super alloc];
	}
	return nil;
}

-(id) init
{
	if((self=[super init])) {
		am = [CDAudioManager sharedManager];
		soundEngine = am.soundEngine;
		bufferManager = [[CDBufferManager alloc] initWithEngine:soundEngine];
		mute_ = NO;
		enabled_ = YES;
	}
	return self;
}

// Memory
- (void) dealloc
{
	am = nil;
	soundEngine = nil;
	bufferManager = nil;
    [_crossFadeTargetTrackFilePath release];
	[super dealloc];
}

+(void) end
{
	am = nil;
	[CDAudioManager end];
	[bufferManager release];
	[sharedEngine release];
	sharedEngine = nil;
}

#pragma mark SimpleAudioEngine - background music

-(void) preloadBackgroundMusic:(NSString*) filePath {
	[am preloadBackgroundMusic:filePath];
}

-(void) playBackgroundMusic:(NSString*) filePath
{
	[am playBackgroundMusic:filePath loop:TRUE];
}

-(void) playBackgroundMusic:(NSString*) filePath loop:(BOOL) loop
{
	[am playBackgroundMusic:filePath loop:loop];
}

-(void) stopBackgroundMusic
{
	[am stopBackgroundMusic];
}

-(void) pauseBackgroundMusic {
	[am pauseBackgroundMusic];
}

-(void) resumeBackgroundMusic {
	[am resumeBackgroundMusic];
}

-(void) rewindBackgroundMusic {
	[am rewindBackgroundMusic];
}

-(BOOL) isBackgroundMusicPlaying {
	return [am isBackgroundMusicPlaying];
}

-(BOOL) willPlayBackgroundMusic {
	return [am willPlayBackgroundMusic];
}

-(void)crossFadeBackgroundMusic:(NSString*) nextFilePath forDuration:(NSTimeInterval)duration
{
    if (self.isBackgroundMusicPlaying && !self.isCrossfading && self.backgroundMusicVolume > 0.0) {
        self.isCrossfading = YES;
        self.crossFadeDuration = duration;
        self.crossFadeProgress = 0.0;
        self.crossFadeTargetTrackFilePath = nextFilePath;
        self.cachedBackgroundVolume = self.backgroundMusicVolume;
        NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/30.0 target:self selector:@selector(crossFadeTick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
}

-(void)crossFadeTick:(NSTimer*)timer
{
    static BOOL didSwitch = NO;
    NSTimeInterval dt = 1.0/30.0;
    self.crossFadeProgress += dt;
    float percentProgress = self.crossFadeProgress / self.crossFadeDuration;
    float targetVolume = 1.0;
    
    if (percentProgress < .5) {
        targetVolume = (1 - (percentProgress * 2)) * self.cachedBackgroundVolume;
    } else {
        targetVolume = (-1 * (1 - (percentProgress * 2))) * self.cachedBackgroundVolume;
    }
    
    self.backgroundMusicVolume = targetVolume;
    
    if (percentProgress >= .5) {
        if (self.crossFadeTargetTrackFilePath && !didSwitch) {
            [self playBackgroundMusic:self.crossFadeTargetTrackFilePath loop:YES];
            didSwitch = YES;
        } else {
            if (!didSwitch) {
                [self stopBackgroundMusic];
            }
        }
    }
    
    if (self.crossFadeProgress >= self.crossFadeDuration) {
        self.isCrossfading = NO;
        self.crossFadeProgress = 0.0;
        self.crossFadeTargetTrackFilePath = nil;
        self.backgroundMusicVolume = self.cachedBackgroundVolume;
        didSwitch = NO;
        [timer invalidate];
    }
}

#pragma mark SimpleAudioEngine - sound effects

-(ALuint) playEffect:(NSString*) filePath
{
	return [self playEffect:filePath pitch:1.0f pan:0.0f gain:1.0f];
}

-(ALuint) playEffect:(NSString*) filePath pitch:(Float32) pitch pan:(Float32) pan gain:(Float32) gain
{
    return [self playEffect:filePath pitch:pitch pan:pan gain:gain loops:false];
}

-(ALuint) playEffect:(NSString*) filePath pitch:(Float32) pitch pan:(Float32) pan gain:(Float32) gain loops:(BOOL)loops
{
    int soundId = [bufferManager bufferForFile:filePath create:YES];
	if (soundId != kCDNoBuffer) {
		return [soundEngine playSound:soundId sourceGroupId:0 pitch:pitch pan:pan gain:gain loop:loops];
	} else {
		return CD_MUTE;
	}
}

-(void) stopEffect:(ALuint) soundId {
	[soundEngine stopSound:soundId];
}

-(void) preloadEffect:(NSString*) filePath
{
	int soundId = [bufferManager bufferForFile:filePath create:YES];
	if (soundId == kCDNoBuffer) {
		CDLOG(@"Denshion::SimpleAudioEngine sound failed to preload %@",filePath);
	}
}

-(void) unloadEffect:(NSString*) filePath
{
	CDLOGINFO(@"Denshion::SimpleAudioEngine unloadedEffect %@",filePath);
	[bufferManager releaseBufferForFile:filePath];
}

#pragma mark Audio Interrupt Protocol
-(BOOL) mute
{
	return mute_;
}

-(void) setMute:(BOOL) muteValue
{
	if (mute_ != muteValue) {
		mute_ = muteValue;
		am.mute = mute_;
	}
}

-(BOOL) enabled
{
	return enabled_;
}

-(void) setEnabled:(BOOL) enabledValue
{
	if (enabled_ != enabledValue) {
		enabled_ = enabledValue;
		am.enabled = enabled_;
	}
}


#pragma mark SimpleAudioEngine - BackgroundMusicVolume
-(float) backgroundMusicVolume
{
	return am.backgroundMusic.volume;
}

-(void) setBackgroundMusicVolume:(float) volume
{
	am.backgroundMusic.volume = volume;
}

#pragma mark SimpleAudioEngine - EffectsVolume
-(float) effectsVolume
{
	return am.soundEngine.masterGain;
}

-(void) setEffectsVolume:(float) volume
{
	am.soundEngine.masterGain = volume;
}

-(CDSoundSource *) soundSourceForFile:(NSString*) filePath {
	int soundId = [bufferManager bufferForFile:filePath create:YES];
	if (soundId != kCDNoBuffer) {
		CDSoundSource *result = [soundEngine soundSourceForSound:soundId sourceGroupId:0];
		CDLOGINFO(@"Denshion::SimpleAudioEngine sound source created for %@",filePath);
		return result;
	} else {
		return nil;
	}
}

@end
