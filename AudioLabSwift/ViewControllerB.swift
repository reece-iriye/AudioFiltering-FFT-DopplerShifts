import UIKit


class ViewControllerB: UIViewController {
    @IBOutlet weak var userView: UIView!
    struct AudioConstants {
        static let AUDIO_BUFFER_SIZE = 4096*4
    }
    
    @IBOutlet weak var motionLabel: UILabel!
    
    @IBOutlet weak var frequencyLabel: UILabel!
    
    @IBOutlet weak var decibelLabel: UILabel!
    
    @IBAction func frequencySlider(_ sender: UISlider) {
        doppler.setFrequency(frequency: sender.value)
        frequencyLabel.text = String(format: "%.0fkHz", sender.value)
    }
    
    
    // setup audio model
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE)
    
    let doppler = DopplerModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE, sineFrequency: 17500)
    
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

            graph.makeGrids() // add grids to graph
        }
        doppler.startMicrophoneProcessing(withFps: 20) // preferred number of FFT calculations per second
        // Begin Audio
        doppler.play()
        
        // run the loop for updating the graph peridocially
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.update()
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
    func update() {
        self.updateGraph()
        self.updateMovement()
    }
    
    func updateGraph() {
        
        if let graph = self.graph{
            graph.updateGraph(
                data: self.doppler.fftData,
                forKey: "fft"
            )
            
            graph.updateGraph(
                data: self.doppler.timeData,
                forKey: "time"
            )
        }
        
    }
        
    func updateMovement() {
        let left = doppler.getLeftMovement()
        let right = doppler.getRightMovement()
        if(left && right) {
            motionLabel.text = "No Movement"
        } else if(right) {
            motionLabel.text = "Moving Away!!!"
        } else if(left) {
            motionLabel.text = "Moving Towards!!!"
        } else {
            motionLabel.text = "No Movement"
        }
    }
}
