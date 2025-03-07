//
//  Audio.swift
//  Flight Data
//
//  Created by ace on 12/23/18.
//  Copyright © 2018 Ace. All rights reserved.
//

import Foundation
import AudioUnit
import CoreAudio

final class Audio: NSObject {
    private var audioUnit: AudioUnit!
    
    // MARK: Audio Variables
    // Constants
    let sampleRate: Float32 = 44100
    let amplitude: Float32 = 1
    let twoPI: Float32 = 2 * Float32.pi
    /*let regFrequency: Float32 = 440
    let alertFrequency: Float32 = 900
    let regInterval: Double = 0.8
    let playSoundLen: Double = 0.2*/
    
    var time: Float32 = 0
    let mainFrequency: Float32 = 440
    let interval: Double = 0.5
    var prevPlayedTime = 0.0
    
    var intervalEnabled = false
    var solidEnabled = false
    lazy var frequency: Float32 = mainFrequency
    
    var hell = false
    var hellOp: (inout Float32, Float32) -> Void = (+=)
    lazy var hellMinFrequency: Float32 = 900
    lazy var hellMaxFrequency: Float32 = 2 * hellMinFrequency
    lazy var hellInterval: Float32 = 0.1
    
    private var muted = true
    /*var playingSound = false
    var prevPlayedTime: Double = 0.0
    var playContinuous = false
    private var muted = true
    var disabled = false*/
    
    /*var hell = false
    var hellOp: (inout Float32, Float32) -> Void = (+=)
    lazy var hellMinFrequency = alertFrequency
    lazy var hellMaxFrequency: Float32 = 2 * alertFrequency*/
    
    var timeFactor: Double = 0
    
    override init() {
        super.init()
        // Calculate timeFactor
        var tinfo = mach_timebase_info(numer: 0, denom: 0)
        let error = mach_timebase_info(&tinfo)
        assert(error == KERN_SUCCESS, "mach_timebase_info Failed")
        timeFactor = Double(exactly: tinfo.numer)! / Double(exactly: tinfo.denom)!
        
        // Configure Audio Component
        var defaultOutputDesc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                          componentSubType: kAudioUnitSubType_RemoteIO,
                                                          componentManufacturer: kAudioUnitManufacturer_Apple,
                                                          componentFlags: 0,
                                                          componentFlagsMask: 0)
        let defaultOutput = AudioComponentFindNext(nil, &defaultOutputDesc)!
        
        var err: OSStatus
        
        // Create a new instance of Audio Component
        err = AudioComponentInstanceNew(defaultOutput, &audioUnit)
        assert(err == noErr, "AudioComponentInstanceNew Failed: " + getError(Int(err)))
        
        // Set the render callback as the input for the Audio Component
        var renderCallbackStruct = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: UnsafeMutableRawPointer(mutating: UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())))
        err = AudioUnitSetProperty(audioUnit,
                                   kAudioUnitProperty_SetRenderCallback,
                                   kAudioUnitScope_Input,
                                   0,
                                   &renderCallbackStruct,
                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        assert(err == noErr, "AudioUnitSetProperty SetRenderCallback Failed: " + getError(Int(err)))
        
        // Set the stream format
        var streamFormat = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate),
                                                       mFormatID: kAudioFormatLinearPCM,
                                                       mFormatFlags: kAudioFormatFlagsNativeFloatPacked|kAudioFormatFlagIsNonInterleaved,
                                                       mBytesPerPacket: 4,
                                                       mFramesPerPacket: 1,
                                                       mBytesPerFrame: 4,
                                                       mChannelsPerFrame: 1,
                                                       mBitsPerChannel: 8 * UInt32(MemoryLayout<Float32>.size),
                                                       mReserved: 0)
        err = AudioUnitSetProperty(audioUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   0,
                                   &streamFormat,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        assert(err == noErr, "AudioUintSetProperty StreamFormat Failed")
    }
    
    func start() {
        var err: OSStatus
        err = AudioUnitInitialize(audioUnit)
        assert(err == noErr, "AudioUnitInitialize Failed: " + getError(Int(err)))
        err = AudioOutputUnitStart(audioUnit)
        assert(err == noErr, "AudioOutputUnitStart Failed: " + getError(Int(err)))
    }
    
    func isMuted() -> Bool {
        return muted
    }
    
    func mute() {
        muted = true
    }
    
    func unmute() {
        muted = false
    }
    
    deinit {
        AudioOutputUnitStop(audioUnit)
        AudioUnitUninitialize(audioUnit)
    }
    
}

private func renderCallback(inRefCon: UnsafeMutableRawPointer,
                            ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            inTimeStamp: UnsafePointer<AudioTimeStamp>,
                            inBusNumber: UInt32,
                            inNumberFrames: UInt32,
                            ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let audio = Unmanaged<Audio>.fromOpaque(inRefCon).takeUnretainedValue()
    let abl = UnsafeMutableAudioBufferListPointer(ioData)
    let buffer = abl![0]
    let pointer: UnsafeMutableBufferPointer<Float32> = UnsafeMutableBufferPointer(buffer)
    
    
    var playingSound = false
    
    let curTime = audio.timeFactor * Double(inTimeStamp.pointee.mHostTime) / 1000000000
    if audio.isMuted() {
        playingSound = false
    } else if audio.solidEnabled {
        playingSound = true
    } else if audio.intervalEnabled {
        audio.frequency = audio.mainFrequency
        if curTime > audio.prevPlayedTime + 2 * audio.interval {
            audio.prevPlayedTime = curTime
            playingSound = true
        } else if curTime > audio.prevPlayedTime + audio.interval {
            playingSound = false
        } else {
            playingSound = true
        }
    } else if audio.hell {
        playingSound = true
    } else {
        playingSound = false
    }
    
    for frame in 0..<inNumberFrames {
        let pointerIndex = pointer.startIndex.advanced(by: Int(frame))
        pointer[pointerIndex] = playingSound ? sin(audio.time) * audio.amplitude : 0
        
        audio.time += audio.twoPI * audio.frequency / audio.sampleRate
        
        if audio.hell {
            audio.hellOp(&audio.frequency, audio.hellInterval)
            if audio.frequency <= audio.hellMinFrequency {
                audio.hellOp = (+=)
            } else if audio.frequency >= audio.hellMaxFrequency {
                audio.hellOp = (-=)
            }
        }
    }
    if audio.time > 100000 {
        audio.time = audio.time.truncatingRemainder(dividingBy: audio.twoPI * audio.frequency)
    }
    return noErr
}

private func getError(_ n: Int) -> String {
    var s: String = String (UnicodeScalar((n >> 24) & 255)!)
    s.append(Character(UnicodeScalar((n >> 16) & 255)!))
    s.append(Character(UnicodeScalar((n >> 8) & 255)!))
    s.append(Character(UnicodeScalar(n & 255)!))
    
    return s
}
