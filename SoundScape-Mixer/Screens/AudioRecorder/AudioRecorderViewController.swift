import AVFoundation
import Foundation
import UIKit

protocol AudioRecorderViewControllerDelegate: class {
    func audioRecorderViewControllerDidSaveRecording(recordingFileURL: URL)
}

// Recording view controller
class AudioRecorderViewController: UIViewController {
    @IBOutlet var recordBtn: UIButton!
    @IBOutlet var pauseBtn: UIButton!
    @IBOutlet var playBtn: UIButton!
    @IBOutlet var timerLbl: UILabel!

    weak var delegate: AudioRecorderViewControllerDelegate?
    var recordingSession: AVAudioSession!
    var audioRecorder: AVAudioRecorder!
    var hasPermission: Bool = false
    var meterTimer: Timer!
    var currentRecordingCount: Int?
    var playing = false

    private var tempRecordingFileURL: URL?
    var finalFileURL: URL?

    private let audioFileExtension = "m4a"

    private var isRecording = false {
        didSet {
            if isRecording {
                pauseBtn.isEnabled = true
            } else {
                if audioRecorder == nil {
                    recordBtn.setTitle("Start recording", for: .normal)
                    pauseBtn.isEnabled = false
                    pauseBtn.setTitle("Pause", for: .normal)
                } else {
                    pauseBtn.setTitle("Resume", for: .normal)
                }
            }
        }
    }

    private var isPaused = false {
        didSet {
            if isPaused {
                pauseBtn.setTitle("Resume", for: .normal)
            } else {
                pauseBtn.setTitle("Pause", for: .normal)
            }
        }
    }

    private var isFinishedRecording = false {
        didSet {
            doneBtn.isEnabled = isFinishedRecording
        }
    }

    lazy var cancelBtn: UIBarButtonItem = {
        let btn = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelBtnPressed))
        return btn
    }()

    lazy var doneBtn: UIBarButtonItem = {
        let btn = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneBtnPressed))
        btn.isEnabled = false
        return btn
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        recordingSession = AVAudioSession.sharedInstance()
        AVAudioSession.sharedInstance().requestRecordPermission { hasPermission in
            self.hasPermission = hasPermission
        }

        setupView()
    }

    // MARK: - Helper methods
    private func setupView() {
        navigationItem.title = "Recorder"
        navigationItem.leftBarButtonItem = cancelBtn
        navigationItem.rightBarButtonItem = doneBtn
    }

    private func showAlert(text: String) {
        let alertVC = UIAlertController()

        alertVC.title = "Infomation"
        alertVC.message = text

        alertVC.addAction(
            UIAlertAction(
                title: "Close", style: .default, handler: { _ in
                    self.dismiss(animated: true, completion: nil)
                }
            )
        )

        present(alertVC, animated: true, completion: nil)
    }

    private func handleSavingRecordingFile(tempURL: URL) {
        guard FileManager.default.fileExists(atPath: tempURL.path) else { return }

        let alertController = UIAlertController(
            title: "Saving audio file",
            message: "Please input your file name", preferredStyle: .alert
        )
        alertController.addTextField { textField in
            textField.placeholder = "New recording"
        }
        
        alertController.addAction(
            UIAlertAction(
                title: "Cancel", style: UIAlertAction.Style.default, handler: { _ in
                    alertController.dismiss(animated: true, completion: nil)
            })
        )

        let confirmAction = UIAlertAction(
            title: "Save",
            style: UIAlertAction.Style.default
        ) { _ in
            // Check if filename already exists
            if let textField = alertController.textFields?.first {
                if let fileName = textField.text,
                    fileName.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                    let url = self.fileManager.recordingsDirectory.appendingPathComponent("\(fileName).\(self.audioFileExtension)")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        // Send file URL
                        self.delegate?.audioRecorderViewControllerDidSaveRecording(recordingFileURL: url)

                        // Replace filename
                        try! FileManager.default.moveItem(at: tempURL, to: url)
                        alertController.dismiss(animated: true, completion: nil)
                        self.dismiss(animated: true, completion: nil)
                    } else {
                        self.displayWarningAlert(
                            withTitle: "Error", errorMessage: "\(fileName) already existed", cancelHandler: {
                                self.handleSavingRecordingFile(tempURL: tempURL)
                            }
                        )
                    }
                } else {
                    self.displayWarningAlert(
                        withTitle: "Error", errorMessage: "Please type a valid name", cancelHandler: {
                            self.handleSavingRecordingFile(tempURL: tempURL)
                        }
                    )
                }
            }
        }

        alertController.addAction(confirmAction)

        present(alertController, animated: true, completion: nil)
    }

    @IBAction func recordBtnPressed(_: Any) {
        if audioRecorder == nil && hasPermission {
            let tempURL = fileManager.recordingsDirectory.appendingPathComponent("NewRecording.\(audioFileExtension)")
            tempRecordingFileURL = tempURL

            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            do {
                try recordingSession.setCategory(.playAndRecord, mode: .default)
                try recordingSession.setActive(true)
                audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
                audioRecorder.isMeteringEnabled = true
                audioRecorder.prepareToRecord()
                audioRecorder.record()

                meterTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateAudioMeter(timer:)), userInfo: nil, repeats: true)

                recordBtn.setTitle("Stop recording", for: .normal)

                isRecording = true
            } catch let err {
                print(err.localizedDescription)
            }
        } else {
            audioRecorder.stop()
            audioRecorder = nil
            isRecording = false
            isFinishedRecording = true
            do {
                try recordingSession.setCategory(.playback, mode: .default)
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    @IBAction func pauseBtnPressed(_: Any) {
        if audioRecorder != nil {
            if isRecording {
                isPaused = true
                isRecording = false
                audioRecorder.pause()
            } else {
                audioRecorder.record()
                isPaused = false
                isRecording = true
            }
        }
    }

    @objc private func cancelBtnPressed() {
        if let tempRecordingFileURL = tempRecordingFileURL {
            do {
                try fileManager.removeItem(at: tempRecordingFileURL)
            } catch {
                print (error)
            }
        }
       
        dismiss(animated: true, completion: nil)
    }

    @objc private func doneBtnPressed() {
        if let temp = tempRecordingFileURL {
            handleSavingRecordingFile(tempURL: temp)
        }
    }

    @IBAction func playButtonTapped(_: Any) {}

    @objc private func updateAudioMeter(timer _: Timer) {
        if let audioRecorder = self.audioRecorder {
            if audioRecorder.isRecording {
                let min = Int(audioRecorder.currentTime / 60)
                let sec = Int(audioRecorder.currentTime.truncatingRemainder(dividingBy: 60))
                let totalTimeString = String(format: "%02d:%02d", min, sec)
                timerLbl.text = totalTimeString
                audioRecorder.updateMeters()

                if sec >= 30 {
                    self.audioRecorder.stop()
                    self.audioRecorder = nil
                    isRecording = false
                    isFinishedRecording = true
                }
            }
        }
    }
}
