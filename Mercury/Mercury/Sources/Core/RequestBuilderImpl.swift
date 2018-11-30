import Foundation

final class RequestBuilderImpl: RequestBuilder {
    private let commonHeadersProvider: CommonHeadersProvider
    
    // MARK: - Init
    
    init(commonHeadersProvider: CommonHeadersProvider)
    {
        self.commonHeadersProvider = commonHeadersProvider
    }
    
    // MARK: - ApiRequest
    
    func buildUrlRequest<R: ApiRequest>(from request: R)
        -> DataResult<URLRequest, RequestError<R.ErrorResponse>>
    {
        switch buildRequestData(from: request) {
        case .error(let error):
            return .error(error)
        case .data(let requestData):
            return URLRequest(url: requestData.url)
                .appendUrlRequestCommonProperties(
                    from: request,
                    headers: requestData.headers
                )
                .appendUrlRequestParameters(
                    from: request,
                    url: requestData.url
            )
        }
    }
    
    func buildUploadRequest<R: UploadMultipartFormDataRequest>(from request: R)
        -> DataResult<R, RequestError<R.ErrorResponse>>
    {
        switch buildRequestData(from: request) {
        case .error(let error):
            return .error(error)
        case .data(let result):
            var request = request
            request.url = result.url.absoluteString
            request.headers = result.headers
            return .data(request)
        }
    }
    
    // MARK: - Private
    
    private func buildRequestData<R: ApiRequest>(from request: R)
        -> DataResult<RequestData, RequestError<R.ErrorResponse>>
    {
        guard let url = buildUrl(from: request) else {
            return .error(.apiClientError(.cantBuildUrl(.cantInitializeUrl)))
        }
        
        return .data(
            RequestData(
                url: url,
                headers: commonHeadersProvider.headersForRequest(request: request)
            )
        )
    }
    
    private func buildUrl<T: ApiRequest>(from request: T) -> URL? {
        let endpointUrl = URL(string: request.endpoint)
        
        var pathComponents = [String]()
        pathComponents.append(request.path)
        
        let normalizedQueryPath = pathComponents.joined(separator: "/").normalizedQueryPath()
        return URL(string: normalizedQueryPath, relativeTo: endpointUrl)
    }
}

private struct RequestData {
    let url: URL
    let headers: [HttpHeader]
}

private extension URLRequest {
    func appendUrlRequestCommonProperties<R: ApiRequest>(
        from request: R,
        headers: [HttpHeader])
        ->  URLRequest
    {
        var urlRequest = self
        urlRequest.appendHttpHeaders(headers)
        urlRequest.httpMethod = request.method.value
        urlRequest.cachePolicy = request.cachePolicy.toNSURLRequestCachePolicy
        return urlRequest
    }
    
    func appendUrlRequestParameters<R: ApiRequest>(
        from request: R,
        url: URL)
        -> DataResult<URLRequest, RequestError<R.ErrorResponse>>
    {
        var urlRequest = self
        var parameters = [String: Any]()
        appendFlatternedParameters(&parameters, fromTreeParameters: request.params, keyPrefix: nil)
        
        let shouldSendParametersInUrl = request.method == .get || request.method == .head
        if shouldSendParametersInUrl {
            let queryString = encodedSortedByKeyStringFrom(dictionary: parameters)
            urlRequest.url = URL(string: url.absoluteString + "?" + queryString)
        } else {
            do {
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
            } catch {
                return .error(.apiClientError(.cantBuildUrl(.cantSerializeHttpBody)))
            }
        }
        
        return .data(urlRequest)
    }
    
    // MARK: - Private
    
    private func appendFlatternedParameters(
        _ flatternedParameters: inout [String: Any],
        fromTreeParameters treeParameters: [String: Any],
        keyPrefix: String?)
    {
        for (key, value) in treeParameters {
            let nextKeyPrefix: String
            
            if let keyPrefix = keyPrefix {
                nextKeyPrefix = "\(keyPrefix)[\(key)]"
            } else {
                nextKeyPrefix = key
            }
            
            if let array = value as? [Any] {
                for (index, item) in array.enumerated() {
                    appendFlatternedParameters(
                        &flatternedParameters,
                        fromTreeParameters: [String(index): item],
                        keyPrefix: nextKeyPrefix
                    )
                }
            } else if let dictionary = value as? [String: Any] {
                appendFlatternedParameters(
                    &flatternedParameters,
                    fromTreeParameters: dictionary,
                    keyPrefix: nextKeyPrefix
                )
            } else {
                flatternedParameters[nextKeyPrefix] = value
            }
        }
    }
    
    private func encodedSortedByKeyStringFrom(dictionary: [String: Any]) -> String {
        var result = ""
        let sortedKeys = dictionary.keys.sorted(by: <)
        
        for key in sortedKeys {
            if let value = dictionary.stringFor(key: key) {
                if !result.isEmpty {
                    result+="&"
                }
                
                let encodedKey = key.byAddingCustomPercentEncodingForChecksumCalculation()
                let encodedValue = value.byAddingCustomPercentEncodingForChecksumCalculation()
                
                result += "\(encodedKey)=\(encodedValue)"
            }
        }
        return result
    }
}
