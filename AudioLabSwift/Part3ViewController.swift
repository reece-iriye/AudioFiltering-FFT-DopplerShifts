//
//  Part3ViewController.swift
//  AudioLabSwift
//
//  Created by Chris Miller on 9/25/23.
//  Copyright © 2023 Eric Larson. All rights reserved.
//

import UIKit

class Part3ViewController: UIViewController {
    @IBOutlet weak var userView: UIView!
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE = 1024*4
    }
    
    // setup audio model
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE)
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.userView)
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let graph = self.graph{
            graph.setBackgroundColor(r: 0, g: 0, b: 0, a: 1)
            
            // add in graphs for display
            // note that we need to normalize the scale of this graph
            // becasue the fft is returned in dB which has very large negative values and some large positive values
            graph.addGraph(withName: "fft",
                            shouldNormalizeForFFT: true,
                            numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE/2)
            
            graph.addGraph(withName: "time",
                           numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
            
            // Creating a third graph for viewing 20 points long
            graph.addGraph(withName: "bufferSize20Graph",
                           shouldNormalizeForFFT: true,
                           numPointsInGraph: audio.maxDataSize20.count)

            graph.makeGrids() // add grids to graph
        }
        
        // Begin Audio
        audio.startProcesingAudioFileForPlayback()
        audio.play()
        
        // run the loop for updating the graph peridocially
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.updateGraph()
        }
       
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause audio manager when navigating away
        audio.pause()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Play audio manager when navigating back
        audio.play()
    }
    
    // periodically, update the graph with refreshed FFT Data
    func updateGraph() {
        
        if let graph = self.graph{
            graph.updateGraph(
                data: self.audio.fftData,
                forKey: "fft"
            )
            
            graph.updateGraph(
                data: self.audio.timeData,
                forKey: "time"
            )
            
            graph.updateGraph(
                data: self.audio.maxDataSize20,
                forKey: "bufferSize20Graph"
            )
        }
        
    }
}
