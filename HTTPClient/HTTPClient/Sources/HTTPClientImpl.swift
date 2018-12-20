import Foundation

public final class HTTPClientImpl: HTTPClient {

    // MARK: - Dependencies
    private let requestBuilder: RequestBuilder
    private let requestRetrier: RequestRetrier
    private let requestDispatcher: RequestDispatcher
    private let uploader: Uploader
    private let operationBuilder: UploadMultipartFormDataRequestOperationBuilder
    private let sendQueue: DispatchQueue
    
    // MARK: - Init
    public init(requestBuilder: RequestBuilder,
                requestRetrier: RequestRetrier,
                requestDispatcher: RequestDispatcher,
                uploader: Uploader,
                operationBuilder: UploadMultipartFormDataRequestOperationBuilder,
                sendQueue: DispatchQueue)
    {
        self.requestBuilder = requestBuilder
        self.requestRetrier = requestRetrier
        self.requestDispatcher = requestDispatcher
        self.uploader = uploader
        self.operationBuilder = operationBuilder
        self.sendQueue = sendQueue
    }
    
    public convenience init(
        commonHeadersProvider: CommonHeadersProvider,
        requestDispatcher: RequestDispatcher) {
        self.init(
            requestBuilder: RequestBuilderImpl(commonHeadersProvider: commonHeadersProvider),
            requestRetrier: RequestRetrierImpl(),
            requestDispatcher: requestDispatcher,
            uploader: AlamofireBackgroundUploader(),
            operationBuilder: AlamofireUploadMultipartFormDataOperationBuilder(),
            sendQueue: DispatchQueue.global(qos: .utility)
        )
    }
    
    public convenience init(
        commonHeadersProvider: CommonHeadersProvider,
        beforeDecodingStrategy: BeforeDecodingStrategy) {
        self.init(
            commonHeadersProvider: commonHeadersProvider,
            requestDispatcher: URLSessionRequestDispatcher(
                session: URLSession.shared,
                responseDecoder: ResponseDecoderImpl(beforeDecodingStrategy: beforeDecodingStrategy)
            )
        )
    }
    
    public convenience init(
        beforeDecodingStrategy: BeforeDecodingStrategy) {
        self.init(
            commonHeadersProvider: CommonHeadersProviderImpl(),
            beforeDecodingStrategy: beforeDecodingStrategy
        )
    }
    
    public convenience init() {
        self.init(
            commonHeadersProvider: CommonHeadersProviderImpl(),
            requestDispatcher: URLSessionRequestDispatcher(
                session: URLSession.shared,
                responseDecoder: ResponseDecoderImpl()
            )
        )
    }
    
    // MARK: - HTTPClient
    @discardableResult
    public func send<R: ApiRequest>(
        request: R,
        completion: @escaping DataResult<R.Result, RequestError<R.ErrorResponse>>.Completion)
        -> NetworkDataTask?
    {
        sendQueue.async {
            self.send(request: request, completion: completion)
        }
        
        return networkDataTask
    }
    
    public func upload<R: UploadMultipartFormDataRequest>(
        dataProvider: DataProvider,
        request: R,
        onProgressChange: ((Progress) -> ())?,
        completion: @escaping DataResult<R.Result, RequestError<R.ErrorResponse>>.Completion)
        -> NetworkDataTask?
    {
        let preparedRequestResult = requestBuilder.buildUploadRequest(from: request)
        
        switch preparedRequestResult {
        case .error(let error):
            completion(.error(error))
            return nil
        case .data(let preparedRequest):
            let uploadOperation = operationBuilder.buildOperation(
                request: preparedRequest,
                dataProvider: dataProvider,
                uploader: uploader,
                onProgressChange: onProgressChange,
                completion: completion
            )

            uploadQueue.addOperation(uploadOperation)

            return OperationDataTask(operation: uploadOperation)
        }
    }
    
    // MARK: - Private
    private let uploadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        return queue
    }()
    
    private var networkDataTask: NetworkDataTask?
    
    private func send<R: ApiRequest>(
        request: R,
        completion: @escaping DataResult<R.Result, RequestError<R.ErrorResponse>>.Completion) {
        let preparedRequestResult = requestBuilder.buildUrlRequest(from: request)
        
        switch preparedRequestResult {
        case .error(let error):
            completion(.error(error))
        case .data(let urlRequest):
            
            if let networkDataTask = networkDataTask, networkDataTask.isCancelled == true {
                return
            }
            
            networkDataTask = requestDispatcher.send(request, urlRequest: urlRequest) { result in
                result.onData { data in
                    DispatchQueue.main.async {
                        completion(.data(data))
                    }
                }
                
                result.onError { [weak self] networkRequestError in
                    if self?.requestRetrier.shouldRetry(policy: request.retryPolicy, request: request) == true {
                        self?.networkDataTask = self?.requestDispatcher.send(
                            request,
                            urlRequest: urlRequest,
                            completion: completion
                        )
                    } else {
                        DispatchQueue.main.async {
                            completion(.error(networkRequestError))
                        }
                    }
                }
            }
        }
    }
}