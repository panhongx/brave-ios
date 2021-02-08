/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/*
 * Value types representing a page's metadata
 */
public struct PageMetadata: Decodable {
    public var id: Int?
    public let siteURL: String
    public let mediaURL: String?
    public let title: String?
    public let description: String?
    public let type: String?
    public let providerName: String?
    public let faviconURL: String?
    public let largeIconURL: String?
    public let keywordsString: String?
    public let feeds: [Feed]
    
    public var keywords: Set<String> {
        guard let string = keywordsString else {
            return Set()
        }

        let strings = string.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        return Set(strings)
    }
    
    enum CodingKeys: String, CodingKey {
        case mediaURL = "image"
        case siteURL = "url"
        case title
        case description
        case type
        case providerName = "provider"
        case faviconURL = "icon"
        case largeIconURL = "largeIcon"
        case keywordsString = "keywords"
        case feeds
    }

    public init(id: Int?, siteURL: String, mediaURL: String?, title: String?, description: String?, type: String?, providerName: String?, faviconURL: String? = nil, largeIconURL: String? = nil, keywords: String? = nil, feeds: [Feed] = []) {
        self.id = id
        self.siteURL = siteURL
        self.mediaURL = mediaURL
        self.title = title
        self.description = description
        self.type = type
        self.providerName = providerName
        self.faviconURL = faviconURL
        self.largeIconURL = largeIconURL
        self.keywordsString = keywords
        self.feeds = feeds
    }
    
    public struct Feed: Decodable {
        public var href: String
        public var title: String
    }
}
