// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import MediaPlayer
import AVKit
import AVFoundation

class PlaylistMediaInfo: NSObject {
    private weak var playerView: VideoView?
    private var cacheLoader = PlaylistCacheLoader()
    private var webLoader = PlaylistWebLoader(handler: { _ in })
    private var streamLoader = MediaResourceManager({ _ in })
    public var nowPlayingInfo: PlaylistInfo? {
        didSet {
            self.updateNowPlayingMediaInfo()
        }
    }
    
    public init(playerView: VideoView) {
        self.playerView = playerView
        super.init()
        
        //playerView.delegate = self
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in
            self?.playerView?.pause()
            return .success
        }
        
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in
            self?.playerView?.play()
            return .success
        }
        
        MPRemoteCommandCenter.shared().stopCommand.addTarget { [weak self] _ in
            self?.playerView?.stop()
            return .success
        }
        
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.addTarget { _ in
            return .success
        }
        
        MPRemoteCommandCenter.shared().changeShuffleModeCommand.addTarget { _ in
            return .success
        }
        
        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget { [weak self] _ in
            self?.playerView?.previous()
            return .success
        }
        
        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { [weak self] _ in
            self?.playerView?.next()
            return .success
        }
        
        MPRemoteCommandCenter.shared().skipBackwardCommand.then {
            $0.preferredIntervals = [NSNumber(value: 15.0)]
        }.addTarget { [weak self] event in
            guard let self = self,
                  let playerView = self.playerView,
                  let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            
            let currentTime = playerView.player.currentTime()
            playerView.seekBackwards()
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime.seconds - event.interval)
            return .success
        }
        
        MPRemoteCommandCenter.shared().skipForwardCommand.then {
            $0.preferredIntervals = [NSNumber(value: 15.0)]
        }.addTarget { [weak self] event in
            guard let self = self,
                  let playerView = self.playerView,
                  let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            
            let currentTime = playerView.player.currentTime()
            playerView.seekForwards()
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime.seconds + event.interval)
            return .success
        }
        
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.playerView?.seek(to: event.positionTime)
            }
            return .success
        }
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        self.updateItems()
        self.updateNowPlayingMediaInfo()
        
        self.playerView?.player.addObserver(self, forKeyPath: "rate", options: .new, context: nil)
    }
    
    deinit {
        self.playerView?.player.removeObserver(self, forKeyPath: "rate", context: nil)
    }
    
    public func updateItems() {
        //playlistItems = Playlist.shared.getItems()
        //contentManager.reloadData()
    }
    
    public func updateNowPlayingMediaInfo() {
        if let nowPlayingItem = self.nowPlayingInfo {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPNowPlayingInfoPropertyMediaType: "Audio",
                MPMediaItemPropertyTitle: nowPlayingItem.name,
                MPMediaItemPropertyArtist: URL(string: nowPlayingItem.pageSrc)?.baseDomain ?? nowPlayingItem.pageSrc,
                MPMediaItemPropertyPlaybackDuration: TimeInterval(nowPlayingItem.duration),
                MPNowPlayingInfoPropertyPlaybackRate: Double(self.playerView?.player.rate ?? 1.0),
                MPNowPlayingInfoPropertyPlaybackProgress: Float(0.0),
                MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(self.playerView?.player.currentTime().seconds ?? 0.0)
            ]
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "rate" {
                self.updateNowPlayingMediaInfo()
            }
        }
}

extension PlaylistMediaInfo: MPPlayableContentDelegate {
    
    private func displayLoadingResourceError() {
        let alert = UIAlertController(title: "Sorry", message: "There was a problem loading the resource!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))
        //self.present(alert, animated: true, completion: nil)
    }
    
    public func loadMediaItem(_ item: PlaylistInfo, completion: @escaping (Error?) -> Void) {
        self.nowPlayingInfo = item
        let cache = Playlist.shared.getCache(item: item)

        if cache.isEmpty {
            if !item.src.isEmpty, let url = URL(string: item.src) {
                //Try to stream the asset from its url..
                MediaResourceManager.canStreamURL(url) { [weak self] canStream in
                    guard let self = self else { return }
                    
                    if canStream {
                        self.playerView?.seek(to: 0.0)
                        self.playerView?.load(url: url, resourceDelegate: nil)
                        completion(nil)
                    } else {
                        //Stream failed so fallback to the webview
                        //It's possible the URL expired..
                        self.webLoader = PlaylistWebLoader(handler: { [weak self] newItem in
                            guard let self = self else { return }
                            if let newItem = newItem, let url = URL(string: newItem.src) {
                                self.playerView?.load(url: url, resourceDelegate: nil)

                                Playlist.shared.updateItem(mediaSrc: item.src, item: newItem) {
                                    DispatchQueue.main.async {
                                        completion(nil)
                                    }
                                }
                            } else {
                                completion("Cannot Load Media")
                            }
                        })
                        
                        if let url = URL(string: item.pageSrc) {
                            self.webLoader.load(url: url)
                        } else {
                            completion("Cannot Load Media")
                        }
                    }
                }
            } else {
                //Fallback to the webview because there was no stream URL somehow..
                webLoader.removeFromSuperview()
                webLoader = PlaylistWebLoader(handler: { [weak self] item in
                    guard let self = self else { return }
                    if let item = item, let url = URL(string: item.src) {
                        self.playerView?.load(url: url, resourceDelegate: nil)
                        completion(nil)
                    } else {
                        completion("Cannot Load Media")
                    }
                })
                self.playerView?.addSubview(webLoader)
                
                if let url = URL(string: item.pageSrc) {
                    webLoader.load(url: url)
                } else {
                    completion("Cannot Load Media")
                }
            }
        } else {
            //Load from the cache since this item was downloaded before..
            self.cacheLoader = PlaylistCacheLoader(cacheData: cache)
            let url = URL(string: "brave-media-ios://local-media-resource?time=\(Date().timeIntervalSince1970)")!
            self.playerView?.load(url: url, resourceDelegate: self.cacheLoader)
            completion(nil)
        }
    }
}

extension PlaylistMediaInfo {
    
    public func thumbnailForURL(_ url: String) -> UIImage? {
        let sourceURL = URL(string: url)
        let asset = AVAsset(url: sourceURL!)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        let time = CMTimeMakeWithSeconds(2, preferredTimescale: 1)
        guard let imageRef = try? imageGenerator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: imageRef)
    }
}

// A resource manager/downloader that is capable of handling HLS streams and content requests
// This is used to determine if a resource is streamable (HLS) and to be able to request chunks of that stream.
class MediaResourceManager: NSObject, AVAssetResourceLoaderDelegate {
    
    private var completion: ((Error?) -> Void)?
    private var dataRequests = [AVAssetResourceLoadingRequest]()
    private var contentInfoRequest: AVAssetResourceLoadingRequest?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: .main)
    private var data = Data()
    
    init(_ completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {

        //Load the content information..
        if let contentRequest = loadingRequest.contentInformationRequest {
            guard let requestURL = loadingRequest.request.url else { return false }
            guard MediaResourceManager.isShimmedURL(requestURL) else { return false }
            let originalURL = MediaResourceManager.unShimURL(requestURL)
            
            //Request for byte-ranges..
            let request: URLRequest = {
                let offset = loadingRequest.dataRequest?.currentOffset ?? 0
                let length = loadingRequest.dataRequest?.requestedLength ?? 0
                
                var request = loadingRequest.request
                request.url = originalURL
                request.addValue("bytes=\(offset)-\(max(1, length - 1))", forHTTPHeaderField: "Range")
                return request
            }()
            
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                guard let response = response as? HTTPURLResponse else {
                    self.completion?("Invalid Response")
                    return
                }
                
                if response.statusCode >= 200 && response.statusCode <= 299 {
                    contentRequest.contentType = response.mimeType
                    contentRequest.contentLength = response.expectedContentLength
                    contentRequest.isByteRangeAccessSupported = response.expectedContentLength != -1
                    
                    if let rangeString = response.allHeaderFields["Content-Range"] as? String,
                        let contentLength = rangeString.split(separator: "/").compactMap({ Int64($0) }).last {
                        contentRequest.contentLength = contentLength
                    }
                    
                    let acceptedRanges = (response.allHeaderFields["Accept-Ranges"] as? String)?.split(separator: ",")
                    if acceptedRanges?.map({ String($0).trim(" ") }).contains("bytes") == true {
                        contentRequest.isByteRangeAccessSupported = true
                    } else {
                        contentRequest.isByteRangeAccessSupported = false
                    }
                } else {
                    self.completion?("Invalid Response")
                    self.completion = nil
                    return
                }
                
                //loadingRequest.dataRequest?.respond(with: data!)
                loadingRequest.finishLoading()
            }.resume()
            contentInfoRequest = loadingRequest
            return true
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            guard let requestURL = loadingRequest.request.url else { return false }
            guard MediaResourceManager.isShimmedURL(requestURL) else { return false }
            let originalURL = MediaResourceManager.unShimURL(requestURL)
            
            //Request for byte-ranges..
            let request: URLRequest = {
                let offset = dataRequest.currentOffset
                let length = dataRequest.requestedLength
                
                var request = URLRequest(url: originalURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.addValue("bytes=\(offset)-\(max(1, length - 1))", forHTTPHeaderField: "Range")
                return request
            }()
            
            //Should use URLSessionDataDelegate to stream instead of downloading all chunks at once..
            self.session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let data = data {
                    self.data.append(data)
                }
                
                self.processPendingRequests()
                
            }.resume()
            
            //session.dataTask(with: request).resume()
            dataRequests.append(loadingRequest)
            return true
        }
        
        return false
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return false
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        if contentInfoRequest == loadingRequest {
            contentInfoRequest = nil
            return
        }
        
        dataRequests.removeAll(where: { loadingRequest == $0 })
    }
    
    func processPendingRequests() {
        let requestsFulfilled = Set<AVAssetResourceLoadingRequest>(self.dataRequests.compactMap {
            $0.contentInformationRequest?.contentLength = Int64(self.data.count)
            $0.contentInformationRequest?.isByteRangeAccessSupported = true
            
            if self.haveEnoughDataToFulfillRequest($0.dataRequest!) {
                $0.finishLoading()
                return $0
            }
            return nil
        })
        
        self.dataRequests.removeAll(where: { requestsFulfilled.contains($0) })
    }
    
    func haveEnoughDataToFulfillRequest(_ dataRequest: AVAssetResourceLoadingDataRequest) -> Bool {
        let requestedOffset = Int(dataRequest.requestedOffset)
        let currentOffset = Int(dataRequest.currentOffset)
        let requestedLength = dataRequest.requestedLength
        
        if currentOffset <= self.data.count {
            let bytesToRespond = min(self.data.count - currentOffset, requestedLength)
            let data = self.data.subdata(in: Range(uncheckedBounds: (currentOffset, currentOffset + bytesToRespond)))
            dataRequest.respond(with: data)
            return self.data.count >= requestedLength + requestedOffset
        }
        
        return false
    }
}

extension MediaResourceManager {
    public static func shimURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let scheme = components?.scheme else { return url }
        components?.scheme = "brave-media-resource" + scheme
        return components?.url ?? url
    }
    
    public static func unShimURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let scheme = components?.scheme else { return url }
        components?.scheme = scheme.replacingOccurrences(of: "brave-media-resource", with: "")
        return components?.url ?? url
    }
    
    public static func isShimmedURL(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let scheme = components?.scheme else { return false }
        return scheme.hasPrefix("brave-media-resource")
    }
    
    //Would be nice if AVPlayer could detect the mime-type from the URL for my delegate without a head request..
    //This function only exists because I can't figure out why videos from URLs don't play unless I explicitly specify a mime-type..
    public static func canStreamURL(_ url: URL, _ completion: @escaping (Bool) -> Void) {
        let request: URLRequest = {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
            request.addValue("bytes=0-1", forHTTPHeaderField: "Range")
            request.addValue(UUID().uuidString, forHTTPHeaderField: "X-Playback-Session-Id")
            request.addValue("AppleCoreMedia/1.0.0.17E255 (iPhone; U; CPU OS 13_4 like Mac OS X; en_ca)", forHTTPHeaderField: "User-Agent")
            return request
        }()
        
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    return completion(false)
                }
                
                if let response = response as? HTTPURLResponse {
                    if response.statusCode == 302 || response.statusCode >= 200 && response.statusCode <= 299 {
                        return completion(true)
                    }
                }
                
                completion(false)
            }
        }.resume()
    }
}