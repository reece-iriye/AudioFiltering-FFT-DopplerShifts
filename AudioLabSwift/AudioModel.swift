//
//  AudioModel.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import Foundation
import Accelerate


struct FFTPeakModel {
    var m2: Float
    var m1: Float
    var m3: Float
    var f2: Int
    var approxPeak: Float
}

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
        // anything not lazily instatntiated should be allocated here
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
        maxDataSize20 = Array.init(repeating: 0.0, count: 20)
    }
    
   
   // Method to find and return peaks from the FFT data.
   func findPeaks() -> [FFTPeakModel] {
       // An array to store detected peaks in FFT data.
       var peakList: [FFTPeakModel] = []
       
       // Use a guard statement to safely unwrap the sampling rate.
       // If it fails, return an empty peakList.
       guard let actualSamplingRate = self.audioManager?.samplingRate else {
           print("Error: Sampling rate is nil.")
           return peakList
       }
       
       // Calculating frequency resolution using the sampling rate and fftData count.
       let freqResolution = Float(actualSamplingRate) / Float(fftData.count)

       // Iterating through each index of fftData, avoiding the first and last indexes.
       for idx in 1...(fftData.count - 2) {
           // Checking if current index (idx) is a peak by comparing it with its neighbors.
           if fftData[idx] > fftData[idx-1] && fftData[idx] > fftData[idx+1] {
               // Assigning magnitude values for current and neighboring indexes for later calculations.
               let m1 = fftData[idx-1]
               let m2 = fftData[idx]
               let m3 = fftData[idx+1]
               
               // Quadratic interpolation to find the approximate true peak frequency.
               let p = (m1 - m3) / (2 * (m3 - (2 * m2) + m1))
               // Calculating the approximated peak frequency.
               print("m1: ", m1)
               print(" m2: ", m2)
               print(" m3: ", m3)
               print("idx: ", idx)
               let approxPeakFreq: Float = (Float(idx) + ((m1 - m3) / ((m3 - (2 * m2) + m1)))) * 93.75
               print("approx: ", approxPeakFreq)
               /*Float(idx) * freqResolution + p * freqResolution / 2*/
               
               // Constructing a peak model object and appending it to peakList.
               let fftPeak = FFTPeakModel(
                   m2: m2,
                   m1: m1,
                   m3: m3,
                   f2: idx,
                   approxPeak: approxPeakFreq
               )
               peakList.append(fftPeak)
           }
       }
       // Returning the list of detected peaks.
       return peakList
    }
    
    // Function to find the top 2 distinct peaks
    func findTopDistinctPeaks() -> [FFTPeakModel] {
        
        // Call the function to obtain all of the sampled peaks
        let peakList: [FFTPeakModel] = self.findPeaks()
        
        // Use a guard statement to safely unwrap the sampling rate.
        // If it fails, return an empty peakList.
        guard let actualSamplingRate = self.audioManager?.samplingRate else {
            print("Error: Sampling rate is nil.")
            return peakList
        }
        
        // Initialize an empty array that will eventually be populated with top peaks
        var topPeaks: [FFTPeakModel] = []
        
        // Sort peaks by magnitude
        let sortedPeaks = peakList.sorted { (peak1, peak2) -> Bool in
            return peak1.m2 > peak2.m2
        }
        
        // Check if there exists a first peak before executing the code block inside
        if let firstPeak = sortedPeaks.first {
            // Add the maximum peak immediately to the topPeaks array before labeling the second highest
            topPeaks.append(firstPeak)
            
            // Iterate through the sorted peaks
            for peak in sortedPeaks {
                // Check if the peak is distinct and add to the top peaks if it is
                // Also ensure that the distance between the peaks is at least 50 Hz
                let isDistinct: Bool = topPeaks.allSatisfy { (existingPeak) -> Bool in
                    return abs(Float(peak.f2 - existingPeak.f2) * actualSamplingRate / self.fftData.count) >= 50.0
                }
                if isDistinct {
                    topPeaks.append(peak)
                    
                    // Exit the loop once 2 peaks are found
                    if topPeaks.count >= 2 {
                        break
                    }
                }
            }
        }
        // Return the top 2 distinct peaks.
        return topPeaks
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
    
    func startProcesingAudioFileForPlayback(){
        self.audioManager?.outputBlock = self.handleSpeakerQueryWithAudioFile
//        self.audioManager?.inputBlock = self.handleSpeaker
        
        Timer.scheduledTimer(withTimeInterval: 1.0/20, repeats: true) { _ in
            self.runEveryInterval()
        }
        
        self.fileReader?.play()
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
    
    // Function to update the peak frequencies.
    func updatePeakFrequencyAmplitude() -> [Float] {
        // Use AudioModel's method to find peaks. No need to pass sampling rate externally.
        let peakList = self.findTopDistinctPeaks()
        print("THE VALUE IN PEAKLIST IS \(peakList)")
        
        // Map peakList to retrieve approximate peak frequencies and display them
        let peakFrequencies = peakList.map { peakModel in
            return peakModel.approxPeak
        }
        
        //print("Peak Frequencies: \(peakFrequencies)")
        
        return peakFrequencies
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
    
    func getTone() -> [Float] {
        let f2 = Float(self.audioManager!.samplingRate) / Float(fftData.count)/2
        var max1:Float = 0.0
        var max2:Float = 0.0
        
        var m2:Float = 0.0
        let windowSize = fftData.count / 100
        for i in 0..<100 {
            let startIdx = i * windowSize
            vDSP_maxv(
                &fftData + startIdx,
                1,
                &m2,
                vDSP_Length(windowSize)
            )
            let maxIndex = Int(fftData.firstIndex(of: m2)!) // Index of local Maximum
            let m1 = fftData[max(maxIndex - 1, 0)]
            //print(m1)
            let m3 = fftData[maxIndex + 1]
//            print("m2: " , m2)
//            print("m1: ", m1)
            if(m2 > 0 && m1 < m2 && m2 > fftData[maxIndex + 1]){ // If value is positive and true local max
                print("here")
                if(max1 == 0.0){
                    max1 = Float(maxIndex)*f2 + (m1 - m3)/(m3 - 2*m2 + m1) * f2/2
                }
                else if(max2 == 0.0){
                    max2 = Float(maxIndex)*f2 + (m1 - m3)/(m3 - 2*m2 + m1) * f2/2
                }
            }
        }
        //print("max1: ", max1)
        return [max1, max2]
    }
    
//    struct FFTPeakModel {
//        var m2: Float;
//        var m1: Float;
//        var m3: Float;
//        var f2: Int;  // Index of fftData
//        // Potentially interpolation value too
//    }
//    
//    var peakList: [self.FFTPeakModel]
//    
//    // Iterate through FFTData
//    for idx in 1...(fftData.count - 2) {
//        if fftData[idx] > fftData[idx-1] && fftData[idx] > fftData[idx+1] {
//            var fftPeak = self.FFTPeak(
//                m2: fftData[idx],
//                m1: fftData[idx-1],
//                m3: fftData[idx+1],
//                f2: idx,
//            )
//            
//            peakList.append(contentsOf: fftPeak)
//        }
//    }
    
    
    
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
    
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
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
