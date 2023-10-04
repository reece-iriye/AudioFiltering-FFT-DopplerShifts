import UIKit
import Metal


class ViewControllerA: UIViewController {
    var lockIn:Bool = true // Bool to lock into frequency
    var labelText:String = "No Frequencies Found"

    @IBOutlet weak var userView: UIView!
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE = 1024*4
    }
    
    @IBOutlet weak var maxLabel: UILabel!
    @IBAction func lockIn(_ sender: Any) {
        lockIn = !lockIn
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
        
        // start up the audio model here, querying microphone
        audio.startMicrophoneProcessing(withFps: 20) // preferred number of FFT calculations per second

        audio.play()
        
        // run the loop for updating the graph peridocially
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Update the graphs that can be seen in the View
            self.updateGraph()
            
            // Then, update the maximum frequencies that are recorded
//            self.updateMaxFrequency()
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
        if(lockIn){ // If unlocked
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
            
            // Get tones of playing frequencies
            let tones = self.audio.getTones()
            if(tones[0] == 0.0){ // Tell user if no tone is found
                labelText = String(format: "No Frequencies Found")
            }
            else if(tones[1] == 0.0){ // Display one frequency if second is not found
                labelText = String(format: "One frequency: %.2f hz", tones[0])
            }
            else{ // Otherwise, displayed the two found frequencies
                labelText = String(format: "Two frequencies: %.2f, %.2f hz", tones[0], tones[1])
            }
            maxLabel.text = labelText // Update label text
        }
    }
    
}
