//
//  DopplerModel.swift
//  AudioLabSwift
//
//  Created by Reece Iriye on 9/27/23.
//

import UIKit

class DopplerModel: NSObject {
    //variables for producing specific frequency
    private var SINE_FREQUENCY:Float
    private var phase:Float = 0.0
    private var phaseIncrement:Float = 0.0
    private var sineWaveRepeatMax:Float = Float(2*Double.pi)
    
    private var decibels:Int
    
    
    private var BUFFER_SIZE:Int
    var timeData:[Float]
    var fftData:[Float]
    
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    init(buffer_size:Int, sineFrequency:Float) {
        BUFFER_SIZE = buffer_size
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        SINE_FREQUENCY = sineFrequency
        decibels = 0
        // anything not lazily instatntiated should be allocated here
        
        
        //timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        //fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        //maxDataSize20 = Array.init(repeating: 0.0, count: 20)
    }
    
    func setDecibels(decibel_read:Int) {
        decibels = decibel_read
    }
    
    func getDecibels() ->Int {
        return self.decibels
    }
    
    func setFrequency(frequency:Float) {
        SINE_FREQUENCY = frequency
    }
    
    func getFrequency() ->Float {
        return self.SINE_FREQUENCY
    }
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double) {
        // setup the microphone to copy to circualr buffer
        if let manager = self.audioManager{
            manager.inputBlock = self.handleMicrophone
            manager.outputBlock = self.handleSpeakerQueryWithSinusoids
            
            // repeat this fps times per second using the timer class
            //   every time this is called, we update the arrays "timeData" and "fftData"
            Timer.scheduledTimer(withTimeInterval: 1.0/withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
            
        }
    }
    
    
    // You must call this when you want the audio to start being handled by our model
    func play(){
        if let manager = self.audioManager {
            manager.play()
        }
    }
    
    //==========================================
    // MARK: Private Properties
    private lazy var audioManager:Novocaine? = {
        return Novocaine.audioManager()
    }()
    
    private lazy var fftHelper:FFTHelper? = {
        return FFTHelper.init(fftSize: Int32(BUFFER_SIZE))
    }()
    
    
    private lazy var inputBuffer:CircularBuffer? = {
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numInputChannels),
                                   andBufferSize: Int64(BUFFER_SIZE))
    }()
    
    //==========================================
    // MARK: Model Callback Methods
    private func runEveryInterval(){
        if inputBuffer != nil {
            // copy time data to swift array
            self.inputBuffer!.fetchFreshData(&timeData, // copied into this array
                                             withNumSamples: Int64(BUFFER_SIZE))
            
            // now take FFT
            fftHelper!.performForwardFFT(withData: &timeData,
                                         andCopydBMagnitudeToBuffer: &fftData) // fft result is copied into fftData array
            
            // at this point, we have saved the data to the arrays:
            //   timeData: the raw audio samples
            //   fftData:  the FFT of those same samples
            // the user can now use these variables however they like
            
        }
    }
    
    //==========================================
    // MARK: Audiocard Callbacks
    // in obj-C it was (^InputBlock)(float *data, UInt32 numFrames, UInt32 numChannels)
    // and in swift this translates to:
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        // copy samples from the microphone into circular buffer
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))
    }
    
    private func handleSpeakerQueryWithSinusoids(data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32){
            if let arrayData = data, let manager = self.audioManager{
                let addFreq:Float = 0
                let mult:Float = 1.0
                phaseIncrement = Float(2*Double.pi*Double(SINE_FREQUENCY+addFreq)/manager.samplingRate)
                
                
                var i = 0
                let chan = Int(numChannels)
                let frame = Int(numFrames)
                if chan==1{
                    while i<frame{
                        arrayData[i] = sin(phase)*mult
                        phase += phaseIncrement
                        if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                        i+=1
                    }
                }else if chan==2{
                    let len = frame*chan
                    while i<len{
                        arrayData[i] = sin(phase)*mult
                        arrayData[i+1] = arrayData[i]
                        phase += phaseIncrement
                        if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                        i+=2
                    }
                }
            }
        }
}
