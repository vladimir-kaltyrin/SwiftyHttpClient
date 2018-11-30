import Foundation

final class AlamofireUploadMultipartFormDataOperationBuilder: UploadMultipartFormDataRequestOperationBuilder {
    func buildOperation<R: UploadMultipartFormDataRequest>(
        request: R,
        dataProvider: DataProvider,
        uploader: Uploader,
        onProgressChange: ((Progress) -> ())?,
        completion: @escaping DataResult<R.Result, RequestError<R.ErrorResponse>>.Completion
        ) -> Operation
    {
        return AlamofireUploadMultipartFormDataRequestOperation(
            request: request,
            dataProvider: dataProvider,
            uploader: uploader,
            onProgressChange: onProgressChange,
            completion: completion
        )
    }
}