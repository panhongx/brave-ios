// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import BraveShared
import Shared
import AVKit
import AVFoundation
import SDWebImage
import CoreData

private let log = Logger.browserLogger

// MARK: PlaylistViewController

class PlaylistViewController: UIViewController {
    
    // MARK: Constants
     
     struct Constants {
        static let playListCellIdentifier = "playlistCellIdentifier"
        static let tableRowHeight: CGFloat = 80
        static let tableHeaderHeight: CGFloat = 11
     }

    // MARK: Properties
    
    private let playerView = VideoView()
    
    private lazy var activityIndicator = UIActivityIndicatorView(style: .white).then {
        $0.isHidden = true
        $0.hidesWhenStopped = true
    }
    
    private let infoLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 12.0, weight: .regular)
        $0.textColor = .white
        $0.textAlignment = .center
        $0.appearanceTextColor = .white
        $0.numberOfLines = 0
        $0.text = Strings.PlayList.playListSectionTitle
    }
    
    private var tableView = UITableView(frame: .zero, style: .grouped).then {
        $0.backgroundView = UIView()
        $0.backgroundColor = BraveUX.popoverDarkBackground
        $0.appearanceBackgroundColor = BraveUX.popoverDarkBackground
        $0.separatorColor = .clear
        $0.appearanceSeparatorColor = .clear
    }
    
    private let formatter = DateComponentsFormatter().then {
        $0.allowedUnits = [.day, .hour, .minute, .second]
        $0.unitsStyle = .abbreviated
        $0.maximumUnitCount = 1
    }

    private lazy var mediaInfo = PlaylistMediaInfo(playerView: playerView)
    
    private var currentlyPlayingItemIndex = -1
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        PlaylistManager.shared.delegate = self
    
        setTheme()
        setup()
        doLayout()

        fetchResults()
    }
    
    // MARK: Internal
    
    private func setTheme() {
        title = Strings.PlayList.playListSectionTitle

        navigationController?.do {
            $0.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
            UILabel.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).appearanceTextColor = .white
            
            $0.presentationController?.delegate = self
            $0.navigationBar.tintColor = .white
            $0.navigationBar.isTranslucent = false
            $0.navigationBar.barTintColor = BraveUX.popoverDarkBackground
            $0.navigationBar.appearanceBarTintColor = BraveUX.popoverDarkBackground
            $0.navigationBar.setBackgroundImage(UIImage(), for: .default)
            $0.navigationBar.shadowImage = UIImage()
        }
        
        view.backgroundColor = BraveUX.popoverDarkBackground
        
        tableView.do {
            $0.contentInset = UIEdgeInsets(top: 0.50 * view.bounds.width, left: 0.0, bottom: 0.0, right: 0.0)
            $0.contentOffset = CGPoint(x: 0.0, y: -0.50 * view.bounds.width)
        }
    }
    
    private func setup () {
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "playlist_exit"), style: .done, target: self, action: #selector(onExit(_:)))
              
        tableView.do {
            $0.register(PlaylistCell.self, forCellReuseIdentifier: Constants.playListCellIdentifier)
            $0.dataSource = self
            $0.delegate = self
        }
        
        playerView.delegate = self
    }
    
    private func doLayout() {
        view.addSubview(tableView)
        view.addSubview(playerView)
        playerView.addSubview(activityIndicator)
        
        playerView.snp.makeConstraints {
            $0.top.equalTo(view.safeArea.top)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(0.50 * view.bounds.width)
        }
        
        activityIndicator.snp.makeConstraints {
            $0.center.equalToSuperview()
        }
        
        tableView.snp.makeConstraints {
            $0.edges.equalTo(view.safeArea.edges)
        }
    }
    
    private func fetchResults() {
        playerView.setControlsEnabled(playerView.player.currentItem != nil)
        updateTableBackgroundView()
        
        DispatchQueue.main.async {
            PlaylistManager.shared.reloadData()
            self.tableView.reloadData()
            
            if PlaylistManager.shared.numberOfAssets() > 0 {
                self.playerView.setControlsEnabled(true)
                self.tableView.delegate?.tableView?(self.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            }
            
            self.updateTableBackgroundView()
        }
    }
    
    // MARK: Actions
    
    @objc
    private func onExit(_ button: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}

// MARK: UIAdaptivePresentationControllerDelegate

extension PlaylistViewController: UIAdaptivePresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .fullScreen
    }
}

// MARK: UITableViewDataSource

extension PlaylistViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlaylistManager.shared.numberOfAssets()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Constants.tableRowHeight
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Constants.tableHeaderHeight
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: Constants.playListCellIdentifier, for: indexPath) as? PlaylistCell else {
            return UITableViewCell()
        }
        
        let item = PlaylistManager.shared.itemAtIndex(indexPath.row)
        
        cell.do {
            $0.selectionStyle = .none
            $0.indicatorIcon.image = #imageLiteral(resourceName: "playlist_currentitem_indicator").template
            $0.indicatorIcon.alpha = 0.0
            $0.titleLabel.text = item.name
            $0.detailLabel.text = formatter.string(from: TimeInterval(item.duration)) ?? "0:00"
            $0.contentView.backgroundColor = .clear
            $0.backgroundColor = .clear
            $0.thumbnailImage = #imageLiteral(resourceName: "menu-NoImageMode")
        }
        
        let cacheState = PlaylistManager.shared.state(for: item.pageSrc)
        if cacheState == .inProgress {
            cell.detailLabel.text = Strings.PlayList.dowloadingLabelTitle
        } else if cacheState == .downloaded {
            cell.detailLabel.text = "\(formatter.string(from: TimeInterval(item.duration)) ?? "0:00") - \(Strings.PlayList.dowloadedLabelTitle)"
        }
        
        if let url = URL(string: item.src) {
            previewImageFromVideo(url: url) {
                cell.thumbnailImage = $0
            }
        }
        
        if indexPath.row == currentlyPlayingItemIndex {
            cell.indicatorIcon.image = #imageLiteral(resourceName: "playlist_currentitem_indicator")
            cell.indicatorIcon.alpha = 1.0
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = UIColor.clear
        
        return headerView
    }
    
    private func previewImageFromVideo(url: URL, _ completion: @escaping (UIImage?) -> Void) {
        let request = URLRequest(url: url)
        let cache = URLCache.shared
        let imageCache = SDImageCache.shared

        if let cachedImage = imageCache.imageFromCache(forKey: url.absoluteString) {
            completion(cachedImage)
            return
        }

        if let cachedResponse = cache.cachedResponse(for: request), let image = UIImage(data: cachedResponse.data) {
            completion(image)
            return
        }

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = false

        let time = CMTimeMake(value: 0, timescale: 600)

        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
            if result == .succeeded, let cgImage = cgImage {
                let image = UIImage(cgImage: cgImage)
                if let data = image.pngData(),
                   let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
                    let cachedResponse = CachedURLResponse(response: response, data: data)
                    cache.storeCachedResponse(cachedResponse, for: request)
                    imageCache.store(image, forKey: url.absoluteString, completion: nil)
                }
                
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                log.error(error)
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: UITableViewDelegate

extension PlaylistViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        if indexPath.row < 0 || indexPath.row >= PlaylistManager.shared.numberOfAssets() {
            return nil
        }

        let currentItem = PlaylistManager.shared.itemAtIndex(indexPath.row)
        let cacheState = PlaylistManager.shared.state(for: currentItem.pageSrc)
        let downloadedItemTitle = cacheState == .invalid ? Strings.download : Strings.PlayList.clearActionButtonTitle
        
        let cacheAction = UIContextualAction(style: .normal, title: downloadedItemTitle, handler: { [weak self] (action, view, completionHandler) in
            guard let self = self else { return }
            
            if cacheState == .inProgress {
                PlaylistManager.shared.cancelDownload(item: currentItem)
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            } else if cacheState == .invalid {
                PlaylistManager.shared.download(item: currentItem)
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            } else {
                PlaylistManager.shared.deleteCache(item: currentItem)
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            
            completionHandler(true)
        })
        
        let deleteAction = UIContextualAction(style: .normal, title: Strings.PlayList.removeActionButtonTitle, handler: { [weak self] (action, view, completionHandler) in
            guard let self = self else { return }
            
            PlaylistManager.shared.delete(item: currentItem)

            if self.currentlyPlayingItemIndex == indexPath.row {
                self.currentlyPlayingItemIndex = -1
                self.mediaInfo.updateNowPlayingMediaInfo()
                
                self.activityIndicator.stopAnimating()
                self.playerView.stop()
            }
            
            completionHandler(true)
        })

        cacheAction.image = cacheState == .invalid ? #imageLiteral(resourceName: "menu-downloads") : #imageLiteral(resourceName: "action_remove")
        cacheAction.backgroundColor = .white
        deleteAction.backgroundColor = #colorLiteral(red: 0.812063769, green: 0.04556301224, blue: 0, alpha: 1)
        
        return UISwipeActionsConfiguration(actions: [deleteAction, cacheAction])
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row < PlaylistManager.shared.numberOfAssets() {
            activityIndicator.startAnimating()
            activityIndicator.isHidden = false
            currentlyPlayingItemIndex = indexPath.row

            let item = PlaylistManager.shared.itemAtIndex(indexPath.row)
            infoLabel.text = item.name
            mediaInfo.loadMediaItem(item, index: indexPath.row) { [weak self] error in
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                
                switch error {
                case .error(let err):
                    log.error(err)
                    self.displayLoadingResourceError()
                    
                case .expired:
                    (tableView.cellForRow(at: indexPath) as? PlaylistCell)?.detailLabel.text = Strings.PlayList.expiredLabelTitle
                    
                case .none:
                    if let url = URL(string: item.src) {
                        self.previewImageFromVideo(url: url) { image in
                            (tableView.cellForRow(at: indexPath) as? PlaylistCell)?.thumbnailImage = image
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                        }
                    }
                }
            }
        }

        tableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        PlaylistManager.shared.reorderItems(from: sourceIndexPath, to: destinationIndexPath)
    }
    
    private func displayLoadingResourceError() {
        let alert = UIAlertController(
            title: Strings.PlayList.sorryAlertTitle, message: Strings.PlayList.loadResourcesErrorAlertDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.PlayList.okayButtonTitle, style: .default, handler: nil))
        
        self.present(alert, animated: true, completion: nil)
    }
}

// MARK: VideoViewDelegate

extension PlaylistViewController: VideoViewDelegate {
    func onPreviousTrack() {
        if currentlyPlayingItemIndex <= 0 {
            return
        }
        
        let index = currentlyPlayingItemIndex - 1
        if index < PlaylistManager.shared.numberOfAssets() {
            let item = PlaylistManager.shared.itemAtIndex(index)
            mediaInfo.loadMediaItem(item, index: index) { [weak self] error in
                if case .none = error {
                    self?.currentlyPlayingItemIndex = index
                } else {
                    self?.displayLoadingResourceError()
                }
            }
        }
    }
    
    func onNextTrack() {
        if currentlyPlayingItemIndex >= PlaylistManager.shared.numberOfAssets() - 1 {
            return
        }
        
        let index = currentlyPlayingItemIndex + 1
        if index >= 0 {
            let item = PlaylistManager.shared.itemAtIndex(index)
            mediaInfo.loadMediaItem(item, index: index) { [weak self] error in
                if case .none = error {
                    self?.currentlyPlayingItemIndex = index
                } else {
                    self?.displayLoadingResourceError()
                }
            }
        }
    }
    
    func onPictureInPicture(enabled: Bool) {
        playerView.pictureInPictureController?.delegate = enabled ? self : nil
    }
    
    func onFullScreen() {
        playerView.player.pause()
        
        let playerController = AVPlayerViewController().then {
            $0.player = playerView.player
            $0.delegate = self
            $0.allowsPictureInPicturePlayback = true
        }
        
        if #available(iOS 14.2, *) {
            playerController.canStartPictureInPictureAutomaticallyFromInline = true
        }
        
        playerController.entersFullScreenWhenPlaybackBegins = true
        
        self.present(playerController, animated: true, completion: {
            playerController.player?.play()
        })
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            print("SUPPORTED")
        } else {
            print("NOT SUPPORTED")
        }
    }
}

// MARK: AVPlayerViewControllerDelegate

extension PlaylistViewController: AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
    
    //TODO: When entering PIP, dismiss the current playlist controller.
    //TODO: When exiting PIP, destroy the video player and its media info. Clear control centre, etc.
    
    // MARK: - AVPlayerViewControllerDelegate
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
        
    }
    
    func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }
    
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
    }
}

extension PlaylistViewController: PlaylistManagerDelegate {
    func onDownloadProgressUpdate(id: String, percentComplete: Double) {
        if let index = PlaylistManager.shared.index(of: id),
           let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? PlaylistCell {
            
            let cacheState = PlaylistManager.shared.state(for: id)
            if cacheState == .inProgress {
                cell.detailLabel.text = "\(Strings.PlayList.dowloadingPercentageLabelTitle) \(percentComplete)%"
            } else if cacheState == .downloaded {
                let item = PlaylistManager.shared.itemAtIndex(index)
                cell.detailLabel.text = "\(formatter.string(from: TimeInterval(item.duration)) ?? "0:00") - \(Strings.PlayList.dowloadedLabelTitle)"
            } else {
                let item = PlaylistManager.shared.itemAtIndex(index)
                cell.detailLabel.text = formatter.string(from: TimeInterval(item.duration)) ?? "0:00"
            }
        }
    }
    
    func onDownloadStateChanged(id: String, state: PlaylistManager.DownloadState, displayName: String) {
        if let index = PlaylistManager.shared.index(of: id),
        let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? PlaylistCell {
            
            if state == .inProgress {
                cell.detailLabel.text = Strings.PlayList.dowloadingLabelTitle
            } else if state == .downloaded {
                let item = PlaylistManager.shared.itemAtIndex(index)
                cell.detailLabel.text = "\(formatter.string(from: TimeInterval(item.duration)) ?? "0:00") - \(Strings.PlayList.dowloadedLabelTitle)"
            } else {
                let item = PlaylistManager.shared.itemAtIndex(index)
                cell.detailLabel.text = formatter.string(from: TimeInterval(item.duration)) ?? "0:00"
            }
        }
    }
    
    func controllerDidChange(_ anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
            case .insert:
                tableView.insertRows(at: [newIndexPath!], with: .fade)
            case .delete:
                tableView.deleteRows(at: [indexPath!], with: .fade)
            case .update:
                tableView.reloadRows(at: [indexPath!], with: .fade)
            case .move:
                tableView.deleteRows(at: [indexPath!], with: .fade)
                tableView.insertRows(at: [newIndexPath!], with: .fade)
            default:
                break
        }
    }
    
    func controllerDidChangeContent() {
        tableView.endUpdates()
    }
    
    func controllerWillChangeContent() {
        tableView.beginUpdates()
    }
}

extension PlaylistViewController {
    func updateTableBackgroundView() {
        if PlaylistManager.shared.numberOfAssets() > 0 {
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
        } else {
            let messageLabel = UILabel(frame: view.bounds).then {
                $0.text = Strings.PlayList.noItemLabelTitle
                $0.textColor = .white
                $0.numberOfLines = 0
                $0.textAlignment = .center
                $0.font = .systemFont(ofSize: 18.0, weight: .medium)
                $0.sizeToFit()
            }
            
            tableView.backgroundView = messageLabel
            tableView.separatorStyle = .none
        }
    }
}
