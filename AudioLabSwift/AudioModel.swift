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
        // anything not lazily instatntiated should be allocated here
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
        
        var tempMax:Float = 0.0
        let windowSize = fftData.count / 100
        for i in 0..<100 {
            let startIdx = i * windowSize
            vDSP_maxv(
                &fftData + startIdx,
                1,
                &tempMax,
                vDSP_Length(windowSize)
            )
            
            let tempIndex = Int(fftData.firstIndex(of: tempMax)!)
            if(tempMax > 0 && fftData[tempIndex - 1] < tempMax && tempMax > fftData[tempIndex + 1]){
                print(tempMax, Float(tempIndex)*f2, i)
                if(max1 == 0.0){
                    max1 = Float(tempIndex)*f2
                }
                else if(max2 == 0.0){
                    max2 = Float(tempIndex)*f2
                }
            }
        }
        
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
