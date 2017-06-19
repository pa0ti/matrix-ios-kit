/*
 Copyright 2017 Vector Creations Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKSoundPlayer.h"

#import <AVFoundation/AVFAudio.h>
#import <AudioToolbox/AudioServices.h>

static const NSTimeInterval kVibrationInterval = 1.24875;

@interface MXKSoundPlayer () <AVAudioPlayerDelegate>

@property (nonatomic, nullable) AVAudioPlayer *audioPlayer;

@property (nonatomic, getter=isVibrating) BOOL vibrating;

@end

@implementation MXKSoundPlayer

+ (instancetype)sharedInstance
{
    static MXKSoundPlayer *soundPlayer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        soundPlayer = [MXKSoundPlayer alloc];
    });
    return soundPlayer;
}

- (void)playSoundAt:(NSURL *)url repeat:(BOOL)repeat vibrate:(BOOL)vibrate routeToBuiltInReciever:(BOOL)useBuiltInReciever
{
    if (self.audioPlayer)
    {
        [self stopPlaying];
    }
    
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
    
    if (!self.audioPlayer)
        return;
    
    self.audioPlayer.delegate = self;
    self.audioPlayer.numberOfLoops = repeat ? -1 : 0;
    [self.audioPlayer prepareToPlay];
    
    // Setup AVAudioSession
    // We use SoloAmbient instead of Playback category to respect silent mode
    NSString *audioSessionCategory = useBuiltInReciever ? AVAudioSessionCategoryPlayAndRecord : AVAudioSessionCategorySoloAmbient;
    [[AVAudioSession sharedInstance] setCategory:audioSessionCategory error:nil];
    
    if (vibrate)
        [self vibrateWithRepeat:repeat];
    
    [self.audioPlayer play];
}

- (void)stopPlaying
{
    if (self.audioPlayer)
    {
        [self.audioPlayer stop];
        self.audioPlayer = nil;
        
        // Release the audio session to allow resuming of background music app
        [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
    
    if (self.isVibrating)
    {
        [self stopVibrating];
    }
}

- (void)vibrateWithRepeat:(BOOL)repeat
{
    self.vibrating = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVibrationInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        
        NSNumber *objRepeat = @(repeat);
        AudioServicesAddSystemSoundCompletion(kSystemSoundID_Vibrate,
                                              NULL,
                                              kCFRunLoopCommonModes,
                                              vibrationCompleted,
                                              (__bridge_retained void * _Nullable)(objRepeat));
    });
}

- (void)stopVibrating
{
    self.vibrating = NO;
    AudioServicesRemoveSystemSoundCompletion(kSystemSoundID_Vibrate);
}

void vibrationCompleted(SystemSoundID ssID, void* __nullable clientData)
{
    NSNumber *objRepeat = (__bridge NSNumber *)clientData;
    BOOL repeat = [objRepeat boolValue];
    CFRelease(clientData);
    
    MXKSoundPlayer *soundPlayer = [MXKSoundPlayer sharedInstance];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVibrationInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (repeat && soundPlayer.isVibrating)
        {
            [soundPlayer vibrateWithRepeat:repeat];
        }
        else
        {
            [soundPlayer stopVibrating];
        }
    });
}

#pragma mark - AVAudioPlayerDelegate

// This method is called only when the end of the player's track is reached.
// If you call `stop` or `pause` on player this method won't be called
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    self.audioPlayer = nil;
    
    // Release the audio session to allow resuming of background music app
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

@end
