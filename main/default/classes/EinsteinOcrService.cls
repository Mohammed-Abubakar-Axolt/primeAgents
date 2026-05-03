public with sharing class EinsteinOcrService {
    public class OcrResult {
        public Boolean success = false;
        public String message;
        public String rawJson;
        public String extractedJson;
    }

    public static OcrResult extractBillData(Id contentVersionId) {
        OcrResult result = new OcrResult();

        if (contentVersionId == null) {
            result.message = 'ContentVersionId is required for OCR extraction.';
            return result;
        }

        ContentVersion versionRecord = [
            SELECT Id, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:Einstein_OCR/v2/vision/ocr');
            request.setMethod('POST');
            request.setTimeout(120000);
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            String body =
                'modelId=' + EncodingUtil.urlEncode('tabulatev2', 'UTF-8') +
                '&task=' + EncodingUtil.urlEncode('invoice', 'UTF-8') +
                '&sampleBase64Content=' + EncodingUtil.urlEncode(
                    EncodingUtil.base64Encode(versionRecord.VersionData),
                    'UTF-8'
                );
            request.setBody(body);

            HttpResponse response = new Http().send(request);
            result.rawJson = response.getBody();

            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                result.success = true;
                result.message = 'Einstein OCR processed the uploaded bill.';
                result.extractedJson = buildExtractedSummary(response.getBody(), versionRecord.Title);
            } else {
                result.message = 'Einstein OCR returned HTTP ' + response.getStatusCode() + '.';
                result.extractedJson = buildPendingSummary(versionRecord.Title, result.message);
            }
        } catch (Exception e) {
            result.message = 'Einstein OCR is not configured or the OCR call failed: ' + e.getMessage();
            result.extractedJson = buildPendingSummary(versionRecord.Title, result.message);
        }

        return result;
    }

    private static String buildExtractedSummary(String rawJson, String title) {
        Map<String, Object> summary = new Map<String, Object>();
        summary.put('source', 'Einstein OCR / Document AI');
        summary.put('documentTitle', title);
        summary.put('status', 'Processed');
        summary.put('rawResponse', rawJson);
        summary.put('processedAt', String.valueOf(System.now()));
        return JSON.serialize(summary);
    }

    private static String buildPendingSummary(String title, String message) {
        Map<String, Object> summary = new Map<String, Object>();
        summary.put('source', 'Einstein OCR / Document AI');
        summary.put('documentTitle', title);
        summary.put('status', 'OCR Configuration Required');
        summary.put('message', message);
        summary.put('processedAt', String.valueOf(System.now()));
        return JSON.serialize(summary);
    }
}
