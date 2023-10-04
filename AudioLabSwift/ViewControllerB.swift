import UIKit


// This view controller (ViewControllerB) is responsible for handling the user interface
// and interactions related to the Doppler effect-based motion detection.
class ViewControllerB: UIViewController {
    // This UIView will display the graph visualization of audio data.
    @IBOutlet weak var userView: UIView!
    
    struct AudioConstants {
        // Define the buffer size for audio data as a higher value to better catch intricate
        // patterns for hand detection alongside peak frequency being played
        static let AUDIO_BUFFER_SIZE = 4096*4
    }
    
    // A label to showcase the motion of the user's hand
    @IBOutlet weak var motionLabel: UILabel!
    
    // A label for displaying the frequency being played based on the slider setting
    @IBOutlet weak var frequencyLabel: UILabel!
    
    // A slider UI element to allow the user to adjust the frequency
    // This helps in fine-tuning the frequency to achieve optimal motion detection
    @IBAction func frequencySlider(_ sender: UISlider) {
        self.doppler.setFrequency(frequency: sender.value)
        // Update the frequency label to reflect the new frequency.
        self.frequencyLabel.text = String(format: "%.0f Hz", sender.value)
    }
    
    // Create an instance of the DopplerModel which will interpret the audio data
    // to determine hand motion relative to the phone
    let doppler = DopplerModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE, sineFrequency: 17500)
    
    // A graph (using Metal framework) to visualize audio data. This helps users
    // understand the audio signals being processed.
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.userView)
    }()
    
    // This function gets called once the view controller loads. It's responsible
    // for setting up the initial state of the UI and audio processing
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
        
        // Start processing microphone input with a preference of 20 FFT calculations per second.
        self.doppler.startMicrophoneProcessing(withFps: 20)
        
        // Begin Audio
        self.doppler.play()
        
        // Schedule a timer to regularly update the graph and other UI components
        // This timer runs every 0.05 seconds (or 20 times a second)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.update()
        }
    }
    
    // This update function will be implemented elsewhere in the code, and will
    // be responsible for refreshing the graphs and updating movement data
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
        
    // Updates the motion label based on the detected movement direction from the FFT analysis.
    func updateMovement() {
        // Fetch boolean values indicating the patterns around the FFT graph peak:
        // 'left' indicates an abnormal pattern to the left of the peak, suggesting
        //      hand is moving towards the phone
        // 'right' indicates an abnormal pattern to the right of the peak, suggesting
        //      hand is moving towards the phone        
        let left = doppler.getLeftMovement()
        let right = doppler.getRightMovement()
        if(left && right) {
            // Likely some sort of error state, defaulting visual in this case to "No Movement"
            self.motionLabel.text = "No Movement"
        } else if(right) {
            self.motionLabel.text = "Moving Away!!!"
        } else if(left) {
            self.motionLabel.text = "Moving Towards!!!"
        } else {
            self.motionLabel.text = "No Movement"
        }
    }
}
