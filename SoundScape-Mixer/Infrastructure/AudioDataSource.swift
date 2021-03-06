import Foundation
import RealmSwift

// Manage audio source
protocol AudioDataSourceDelegate: NSObjectProtocol {
    func audioDataSource(_ dataSource: AudioDataSource, didFetchAudioWithError error: Error)
    func audioDataSource(_ dataSource: AudioDataSource, didFinishDownloadingWithItems items: [Audio])
    func audioDataSource(_ dataSource: AudioDataSource, didSelectAudio audio: Audio)
}

extension AudioDataSourceDelegate {
    func audioDataSource(_: AudioDataSource, didFetchAudioWithError _: Error) {}
    func audioDataSource(_: AudioDataSource, didFinishDownloadingWithItems _: [Audio]) {}
    func audioDataSource(_: AudioDataSource, didSelectAudio _: Audio) {}
}

class AudioDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
    private let player = AudioPlayer.sharedInstance
    private let realm = try! Realm()
    private var playingCellIndex: IndexPath?
    private(set) lazy var items = realm.objects(Audio.self).filter("category == %@", audioCategory.rawValue)
    private var observationToken: NotificationToken?
    private var searching = false
    private var searchText: String?
    private var displayItems: Results<Audio> {
        guard let text = searchText, text.trimmingCharacters(in: .whitespacesAndNewlines) != "" else {
            return items
        }
        return items.filter("title CONTAINS %@", text)
    }
    
    var audioCategory: AudioCategory!
    var audioService: AudioService!
    var cellViewModels: [AudioCollectionViewCellModel] = []
    
    weak var delegate: AudioDataSourceDelegate?
    
    /// Colletion view
    weak var collectionView: UICollectionView? {
        willSet {
            collectionView?.delegate = nil
            collectionView?.dataSource = nil
        }
        didSet {
            collectionView?.registerNib(AudioCollectionViewCell.self)
            collectionView?.delegate = self
            collectionView?.dataSource = self
        }
    }
    
    // MARK: Life cycle methods
    init(category: AudioCategory) {
        audioCategory = category
        super.init()
        
        observationToken = items.observe(
            { _ in
                self.cellViewModels = self.items.map {
                    let downloaded = FileManager.default.downloadedFileExist(for: $0)
                    return AudioCollectionViewCellModel.viewModel(
                        for: $0,
                        downloading: false,
                        downloaded: downloaded,
                        progress: 0.0
                    )
                }
                self.collectionView?.reloadData()
            }
        )
        
        NotificationCenter.default.addObserver(self, selector: #selector(audioPlayerDidFinishPlaying), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        
        DownloadService.shared.delegates.add(self)
    }
    
    // MARK: - Utils methods
    
    /// Fetch remote items
    func refresh() {
        audioService.getCategoryAudio(category: audioCategory.rawValue) { [weak self] audioArray, error in
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                if let err = error {
                    strongSelf.delegate?.audioDataSource(strongSelf, didFetchAudioWithError: err)
                    return
                }
                
                var items = [Audio]()
                if let audio = audioArray {
                    items = audio.compactMap { $0.first }
                    
                    try! strongSelf.realm.write {
                        strongSelf.realm.add(items, update: true)
                    }
                }
                strongSelf.delegate?.audioDataSource(strongSelf, didFinishDownloadingWithItems: items)
            }
        }
    }
    
    func search(_ searchText: String) {
        self.searchText = searchText
        cellViewModels = cellViewModels(for: displayItems)
        collectionView?.reloadData()
    }
    
    func endSearching() {
        searchText = nil
        cellViewModels = cellViewModels(for: displayItems)
        collectionView?.reloadData()
    }
    
    @objc func audioPlayerDidFinishPlaying() {
        if let indexPath = playingCellIndex {
            cellViewModels[indexPath.row].isPlaying = false
            collectionView?.reloadItems(at: [indexPath])
            playingCellIndex = nil
        }
    }
    
    // MARK: - Helper methods
    private func cellViewModels(for results: Results<Audio>) -> [AudioCollectionViewCellModel] {
        return results.map {
            let downloaded = FileManager.default.downloadedFileExist(for: $0)
            return AudioCollectionViewCellModel.viewModel(
                for: $0,
                downloading: false,
                downloaded: downloaded,
                progress: 0.0
            )
        }
    }
    
    // MARK: UICollectionViewDataSource methods
    func numberOfSections(in _: UICollectionView) -> Int { return 1 }
    
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        return cellViewModels.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: AudioCollectionViewCell = collectionView.dequeueReusableCell(forRowAtIndexPath: indexPath)
        cell.delegate = self
        
        let cellViewModel = cellViewModels[indexPath.row]
        cell.setup(
            downloaded: cellViewModel.downloaded,
            downloading: cellViewModel.downloading,
            progress: cellViewModel.progress
        )
        cell.playing = cellViewModel.isPlaying
        cell.audioNameLabel.text = cellViewModel.title
        
        // TODO: Remove this line
        cell.progressView.setProgress(cellViewModel.progress, animated: true)
        
        if (audioCategory == AudioCategory.recording) {
            cell.downloadButton.isHidden = true
        }
        
        return cell
    }
    
    // MARK: UICollectionViewDelegate methods
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let audio = displayItems[indexPath.row]
        delegate?.audioDataSource(self, didSelectAudio: audio)
    }
}

// MARK: - AudioCollectionViewCellDelegate methods
extension AudioDataSource: AudioCollectionViewCellDelegate {
    func audioCollectionViewCellDidTapStartDownloadButton(_ cell: AudioCollectionViewCell) {
        guard let indexPath = collectionView?.indexPath(for: cell) else {
            return
        }
        let audio = items[indexPath.row]
        var cellViewModel = cellViewModels[indexPath.row]
        cellViewModel.downloading = true
        cellViewModels[indexPath.row] = cellViewModel
        
        collectionView?.reloadItems(at: [indexPath])
        
        DownloadService.shared.download(audio)
    }
    
    func audioCollectionViewCellDidTapPauseDownloadButton(_: AudioCollectionViewCell) {}
    
    func audioCollectionViewCellDidTapCancelDownloadButton(_: AudioCollectionViewCell) {}
    
    func audioCollectionViewCellDidTapPlayButton(_ cell: AudioCollectionViewCell) {
        if let playingIndexPath = playingCellIndex {
            playAudio(false, at: playingIndexPath.row)
            player.stopAudio()
            playingCellIndex = nil
        }
        
        guard let indexPath = collectionView?.indexPath(for: cell) else { return }
        playingCellIndex = indexPath
        
        // Update UI
        playAudio(true, at: indexPath.row)
        let cellViewModel = cellViewModels[indexPath.row]
        
        var audioFileURL: URL?
        
        if let urlString = cellViewModel.url, let url = URL(string: urlString) {
            if cellViewModel.downloaded {
                audioFileURL = FileManager.default.documentDirectory.appendingPathComponent(url.lastPathComponent)
            } else {
                audioFileURL = url
            }
        }
        
        if let fileURL = audioFileURL {
            player.playAudio(url: fileURL)
        }
    }
    
    // Update UI
    private func playAudio(_ shouldPlay: Bool, at index: Int) {
        var cellViewModel = cellViewModels[index]
        cellViewModel.isPlaying = shouldPlay
        
        cellViewModels[index] = cellViewModel
        collectionView?.reloadItems(at: [IndexPath(row: index, section: 0)])
    }
}

extension AudioDataSource: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt _: IndexPath
        ) -> CGSize {
        let width = UIScreen.main.bounds.size.width
        return CGSize(width: width, height: 55.0)
    }
}

// MARK: - DownloadServiceDelegate methods
extension AudioDataSource: DownloadServiceDelegate {
    func downloadServiceDidFinishDownloading(_: DownloadService, operation: DownloadOperation) {
        guard let fileLocation = operation.downloadedFileURL else { return }
        
        let destinationURL = FileManager.default.localFileURL(for: operation.url)
        try? FileManager.default.removeItem(at: destinationURL)
        
        // Reload UI
        DispatchQueue.main.sync {
            if var cellViewModel = self.cellViewModels.filter({ URL(string: $0.url!)! == operation.url }).first,
                let index = self.cellViewModels.index(of: cellViewModel) {
                cellViewModel.downloaded = true
                cellViewModel.downloading = false
                self.cellViewModels[index] = cellViewModel
                collectionView?.reloadItems(at: [IndexPath(row: index, section: 0)])
            }
        }
        
        do {
            try FileManager.default.copyItem(at: fileLocation, to: destinationURL)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func downloadService(_: DownloadService, operation: DownloadOperation, didUpdateProgress progress: Float) {
        DispatchQueue.main.async {
            if var cellViewModel = self.cellViewModels.filter({ URL(string: $0.url!)! == operation.url }).first,
                let index = self.cellViewModels.index(of: cellViewModel) {
                cellViewModel.downloaded = false
                cellViewModel.progress = progress
                cellViewModel.downloading = true
                
                self.cellViewModels[index] = cellViewModel
                self.collectionView?.reloadItems(at: [IndexPath(row: index, section: 0)])
            }
        }
    }
}
