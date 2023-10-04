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
    
    private var decibels:Float
    
    
    private var BUFFER_SIZE:Int
    private var peakIndex:Int
    private var motionWindow:Int
    private var leftMovement:Bool
    private var rightMovement:Bool
    private var checkMotion:Bool
    
    var timeData:[Float]
    var fftData:[Float]
    var decibelData:[Float]
    
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    init(buffer_size:Int, sineFrequency:Float) {
        BUFFER_SIZE = buffer_size
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        decibelData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        SINE_FREQUENCY = sineFrequency
        decibels = 0
        peakIndex = 0
        motionWindow = 10
        leftMovement = false
        rightMovement = false
        checkMotion = true
        // anything not lazily instatntiated should be allocated here
        
        
        //timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        //fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        //maxDataSize20 = Array.init(repeating: 0.0, count: 20)
    }
    
    func setDecibels(decibel_read:Float) {
        decibels = decibel_read
    }
    
    func getDecibels() ->Float {
        return self.decibels
    }
    
    func getLeftMovement() ->Bool {
        return leftMovement
    }
    
    func getRightMovement() ->Bool {
        return rightMovement
    }
    
    func calculateDecibelData() {
        self.peakIndex = 0
        for i in 0...(fftData.count-1) {
            if(i > fftData.count/2) && (fftData[i] > fftData[peakIndex]) {
                peakIndex = i
            }
            if(fftData[i] != 0 && !fftData[i].isInfinite){
                decibelData[i] = log10(2*(fftData[i]*fftData[i]))
                if decibelData[i] > decibels {
                    decibels = decibelData[i]
                }
            } else {
                decibelData[i] = 0;
            }
        }
    }
    
    func calculateMotion() {
        let rightMotion = max(0, peakIndex-motionWindow)
        let leftMotion = min(decibelData.count-1, peakIndex+motionWindow)
        //print(String(format: "Left Motion: %.0f", fftData[leftMotion]))
        //print(String(format: "Peak: %.0f", fftData[peakIndex]))
        //print(String(format: "Right Motion: %.0f", fftData[rightMotion]))
        guard let sample = audioManager?.samplingRate else{
            return
        }
        print(sample/Double(fftData.count))
        if(checkMotion) {
            if((fftData[peakIndex] - fftData[rightMotion]) < 35 && (fftData[rightMotion] - fftData[leftMotion]) > 25){
                rightMovement = true
                leftMovement = false
                checkMotion = false
                
            } else if((fftData[peakIndex] - fftData[leftMotion]) < 35 && (fftData[leftMotion] - fftData[rightMotion]) > 25){
                leftMovement = true
                rightMovement = false
                checkMotion = false
                
            } else if((fftData[peakIndex] - fftData[leftMotion]) < 35 && (fftData[peakIndex] - fftData[rightMotion]) < 35){
                leftMovement = true
                rightMovement = true
                checkMotion = false
            } else{
                leftMovement = false
                rightMovement = false
            }
        } else{
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                self.checkMotion = true
            }
        }
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
            
            calculateDecibelData()
            
            calculateMotion()
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
                        arrayData[i] = 10*sin(phase)*mult
                        phase += phaseIncrement
                        if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                        i+=1
                    }
                }else if chan==2{
                    let len = frame*chan
                    while i<len{
                        arrayData[i] = 10*sin(phase)*mult
                        arrayData[i+1] = arrayData[i]
                        phase += phaseIncrement
                        if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                        i+=2
                    }
                }
            }
        }
}
