//
//  DopplerModel.swift
//  AudioLabSwift
//
//  Created by Reece Iriye on 9/27/23.
//

import UIKit

// The DopplerModel is responsible for processing audio data and determining
// motion based on the Doppler effect
class DopplerModel: NSObject {
    // Constants and variables for generating specific sine wave frequency
    private var SINE_FREQUENCY:Float
    private var phase:Float = 0.0
    private var phaseIncrement:Float = 0.0
    private var sineWaveRepeatMax:Float = Float(2*Double.pi)
    
    // Store the decibel value
    private var decibels:Float
    
    // Variables for buffer and motion detection
    private var BUFFER_SIZE:Int
    private var peakIndex:Int
    private var motionWindow:Int
    private var leftMovement:Bool
    private var rightMovement:Bool
    private var checkMotion:Bool
    
    // Arrays to store audio time, FFT, and decibel data.
    var timeData:[Float]
    var fftData:[Float]
    var decibelData:[Float]
    
    // Sampling rate of audio
    lazy var samplingRate:Int = {
        return Int(self.audioManager!.samplingRate)
    }()
    
    // Initialization of the DopplerModel with buffer size and sine frequency
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
    }
    
    // Getters and setters for controller to access on changing view label
    func getLeftMovement() -> Bool {
        return self.leftMovement
    }
    
    func getRightMovement() -> Bool {
        return self.rightMovement
    }
    
    func calculateMotion() {
        // Determine the indices for the right and left of the peak in the FFT data,
        // considering the size of the motionWindow.
        let rightMotion = max(0, self.peakIndex - self.motionWindow)
        let leftMotion = min(self.decibelData.count-1, self.peakIndex+motionWindow)

        // Ensure that we have a sampling rate from the audio manager.
        guard let sample = self.audioManager?.samplingRate else {
            return
        }
        
        // Check if motion determination is currently allowed (sometimes disables to ensure sampling
        // isn't too frequent)
        // ⭐: The numbers 35 and 25 were arbitrarily used, as they tended to capture correct motions
        //      in testing
        if(self.checkMotion) {
            if((self.fftData[peakIndex] - self.fftData[rightMotion]) < 35
               && (self.fftData[rightMotion] - self.fftData[leftMotion]) > 25) {
                // Determine if the movement is to the right.
                // If the difference between the peak and the value to its right is below 35,
                // and the difference between the value to its right and the value to its left is above 25,
                // we can consider it a rightward movement.
                self.rightMovement = true
                self.leftMovement = false
                self.checkMotion = false
            } else if((self.fftData[self.peakIndex] - self.fftData[leftMotion]) < 35
                      && (self.fftData[leftMotion] - self.fftData[rightMotion]) > 25) {
                // Determine if the movement is to the left.
                // Similar logic, but looking at the difference between the peak and its left,
                // and the difference between its left and right.
                self.leftMovement = true
                self.rightMovement = false
                self.checkMotion = false
            } else if((self.fftData[peakIndex] - self.fftData[leftMotion]) < 35 && (self.fftData[self.peakIndex] - fftData[rightMotion]) < 35){
                // Determine if there is movement in both directions.
                // If the differences from the peak to both the left and right are below 35,
                // it indicates simultaneous movement in both directions, which is an error state that
                // we track as lack of movement for the user to see.
                self.leftMovement = true
                self.rightMovement = true
                self.checkMotion = false
            } else{
                // If none of the above conditions are met, then there's no detectable movement
                self.leftMovement = false
                self.rightMovement = false
            }
        } else{
            // If motion determination is currently not allowed,
            // set a timer to enable motion checking after a 0.5-second delay.
            // This is to avoid rapidly toggling motion detection.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                self.checkMotion = true
            }
        }
    }
    
    // Getters and setters for sine frequency in playing audio
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
            self.fftHelper!.performForwardFFT(withData: &timeData,
                                         andCopydBMagnitudeToBuffer: &fftData) // fft result is copied into fftData array
            
            
            self.calculateMotion()
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
        // Check if data exists and if the audio manager is set
        if let arrayData = data, let manager = self.audioManager{
            // An optional frequency adjustment; by default, it's 0
            let addFreq:Float = 0
            
            // A multiplier that can be used to adjust the amplitude of the sine wave.
            // Currently, it's set to 10.
            let mult:Float = 10.0
            
            // Calculate the phase increment based on the desired frequency
            // The phase increment determines how much we should increase the phase for each sample to produce the desired frequency
            phaseIncrement = Float(2*Double.pi*Double(SINE_FREQUENCY+addFreq)/manager.samplingRate)
            
            
            var i = 0
            let chan = Int(numChannels)
            let frame = Int(numFrames)

            // For each audio frame...
            while i<frame {
                // Generate a sine wave sample at the current phase, and adjust its amplitude using 'mult'.
                arrayData[i] = sin(phase)*mult
                
                // Increase the phase by the precomputed increment.
                phase += phaseIncrement
                
                // If the phase goes beyond our maximum, wrap it around (essentially keeping the phase between 0 and 2*Pi).
                if (phase >= sineWaveRepeatMax) { phase -= sineWaveRepeatMax }
                
                i+=1
            }

        }
    }
}
