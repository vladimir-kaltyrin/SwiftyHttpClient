import Foundation
import Alamofire

extension SessionManager {
    static let background: SessionManager = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.httpClient.uploader")
        configuration.httpAdditionalHeaders = SessionManager.defaultHTTPHeaders
        
        return SessionManager(configuration: configuration)
    }()
}

final class AlamofireBackgroundUploader: AlamofireUploader {
    
    func upload(
        multipartFormData: @escaping (MultipartFormData) -> Void,
        to url: URLConvertible,
        method: HTTPMethod = .post,
        headers: HTTPHeaders? = nil,
        encodingCompletion: ((SessionManager.MultipartFormDataEncodingResult) -> Void)?)
    {
        return SessionManager.background.upload(
            multipartFormData: multipartFormData,
            usingThreshold: SessionManager.multipartFormDataEncodingMemoryThreshold,
            to: url,
            method: method,
            headers: headers,
            encodingCompletion: encodingCompletion
        )
    }
}
