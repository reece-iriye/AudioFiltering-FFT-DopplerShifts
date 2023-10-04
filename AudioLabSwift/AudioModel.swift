//
//  AudioModel.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import Foundation
import Accelerate


class AudioModel {
    
    // MARK: Properties
    private var BUFFER_SIZE:Int
    // thse properties are for interfaceing with the API
    // the user can access these arrays at any time and plot them if they like
    var timeData:[Float]
    var fftData:[Float]
    var maxDataSize20:[Float]  // size 20 array for max frequency per buffer
    
    // MARK: Public Methods
    init(buffer_size:Int) {
        BUFFER_SIZE = buffer_size
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        maxDataSize20 = Array.init(repeating: 0.0, count: 20)
    }
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double){
        // setup the microphone to copy to circualr buffer
        if let manager = self.audioManager{
            self.audioManager?.outputBlock = nil
            manager.inputBlock = self.handleMicrophone
            
            
            // repeat this fps times per second using the timer class
            //   every time this is called, we update the arrays "timeData" and "fftData"
            Timer.scheduledTimer(withTimeInterval: 1.0/withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
        }
    }
    
    // You must call this when you want the audio to start being handled by our model
    func play(){
        if let manager = self.audioManager{
            manager.play()
        }
    }
    
    func pause(){
        if let manager = self.audioManager{
            manager.pause()
        }
    }
    
    func updateMaxFrequencyAmplitude() {
        // Window size for each slice of the FFT array
        let windowSize = fftData.count / maxDataSize20.count

        // Use vDSP_maxv to get the maximum value for each window
        for i in 0..<maxDataSize20.count {
            let startIdx = i * windowSize  // Starting index
            
            // Note: vDSP_maxv used pass by reference to adjust maximum value in the given Float array
            vDSP_maxv(
                &fftData + startIdx, // Starting point in memory to reference
                1, // Stride
                &maxDataSize20 + i, // The point in memory to modify by inputting the max
                vDSP_Length(windowSize) // The length of the area to analyze after `&fftData + startIdx`
            )
        }
    }
    
    // This function identifies and returns the frequencies of the two most prominent peaks
    // in the FFT data, possibly corresponding to two played tones. Interpolation is employed
    // to improve frequency resolution and more accurately determine the peak frequencies.
    func getTones() -> [Float] {
        // Calculate the frequency resolution (delta frequency between FFT bins)
        let f2 = Float(self.audioManager!.samplingRate) / Float(fftData.count)/2 // (Sampling frequency / N)
        
        var max1:Float = 0.0  // Frequency of the first detected peak
        var max2:Float = 0.0  // Frequency of the second detected peak
        
        var m2:Float = 0.0  // Used to store the value of the current local maximum in the FFT data

        // Define the window size for localized peak finding. This window size allows
        // us to detect peaks that are within 50Hz of each other.
        let windowSize = fftData.count / 1000
        
        for i in 0..<1000 {
            let startIdx = i * windowSize + 25  // Compute the starting index for the current window
            
            // Note: vDSP_maxv used pass by reference to adjust maximum value in the given Float array
            vDSP_maxv(
                &fftData + startIdx,
                1,
                &m2,
                vDSP_Length(windowSize)
            )
            
            let maxIndex = Int(fftData.firstIndex(of: m2)!)  // Get the index of the found maximum
            let m1 = fftData[max(maxIndex - 1, 0)]  // Value just before the maximum
            let m3 = fftData[maxIndex + 1]  // Value just after the maximum
            
            // Quadratic interpolation: Using the detected peak and its neighbors,
            // we can estimate the actual peak frequency with more precision.
            // We do this by fitting a parabola through the three points and finding its vertex.
            let interpolationFactor = (m1 - m3) / (m3 - 2*m2 + m1)
            
            // Check if the point is indeed a local maximum: its value should be positive
            // and greater than both of its neighbors
            if(m2 > 0 && m1 < m2 && m2 > m3){ // If max is positive and greater than surround point
                if(max1 == 0.0){  // If the first peak hasn't been identified yet
                    max1 = Float(maxIndex) * f2 + interpolationFactor * f2 / 2
                }
                else if (max2 == 0.0) {  // If the second peak hasn't been identified yet
                    max2 = Float(maxIndex) * f2 + interpolationFactor * f2 / 2
                }
            }
        }
        // Return the two detected peak frequencies
        return [max1, max2]
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
    
    private lazy var outputBuffer:CircularBuffer? = {
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numOutputChannels),
                                   andBufferSize: Int64(BUFFER_SIZE))
    }()
    
    //==========================================
    // MARK: Private Methods
    private lazy var fileReader:AudioFileReader? = {
        
        if let url = Bundle.main.url(forResource: "satisfaction", withExtension: "mp3"){
            var tmpFileReader:AudioFileReader? = AudioFileReader.init(audioFileURL: url,
                                                   samplingRate: Float(audioManager!.samplingRate),
                                                   numChannels: audioManager!.numOutputChannels)
            
            tmpFileReader!.currentTime = 0.0
            print("Audio file succesfully loaded for \(url)")
            return tmpFileReader
        }else{
            print("Could not initialize audio input file")
            return nil
        }
    }()
    
    //==========================================
    // MARK: Model Callback Methods
    private func runEveryInterval(){
        if inputBuffer != nil {
            // copy time data to swift array
            self.inputBuffer!.fetchFreshData(&timeData,
                                             withNumSamples: Int64(BUFFER_SIZE))
            
            // now take FFT
            fftHelper!.performForwardFFT(withData: &timeData,
                                         andCopydBMagnitudeToBuffer: &fftData)
            
            // at this point, we have saved the data to the arrays:
            //   timeData: the raw audio samples
            //   fftData:  the FFT of those same samples
            // the user can now use these variables however they like
            
            updateMaxFrequencyAmplitude()
        }
    }
    
    private func handleMicrophone(data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        // copy samples from the microphone into circular buffer
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))
    }
    
    private func handleSpeakerQueryWithAudioFile(data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32){
        if let file = self.fileReader{
            
            // read from file, loaidng into data (a float pointer)
            file.retrieveFreshAudio(data,
                                    numFrames: numFrames,
                                    numChannels: numChannels)
            
            // set samples to output speaker buffer
            self.outputBuffer?.addNewFloatData(data,
                                         withNumSamples: Int64(numFrames))
            self.inputBuffer?.addNewFloatData(data,
                                         withNumSamples: Int64(numFrames))
        }
    }
}
