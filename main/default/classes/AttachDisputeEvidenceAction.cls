public with sharing class AttachDisputeEvidenceAction {
    public class ActionInput {
        @InvocableVariable(required=true) public String caseId;
        @InvocableVariable public String contentVersionId;
        @InvocableVariable public String contentDocumentId;
    }

    public class ActionOutput {
        @InvocableVariable public Boolean success;
        @InvocableVariable public Boolean evidenceReceived;
        @InvocableVariable public Boolean ocrProcessed;
        @InvocableVariable public String caseId;
        @InvocableVariable public String contentDocumentId;
        @InvocableVariable public String extractedDataJson;
        @InvocableVariable public String messageText;
    }

    @InvocableMethod(label='Attach Dispute Evidence' description='Links an uploaded WhatsApp bill image to the dispute and processes it with Einstein OCR.' callout=true)
    public static List<ActionOutput> attachEvidence(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            output.success = false;
            output.evidenceReceived = false;
            output.ocrProcessed = false;
            output.caseId = input.caseId;

            Id contentVersionId = String.isBlank(input.contentVersionId) ? null : (Id) input.contentVersionId;
            Id contentDocumentId = String.isBlank(input.contentDocumentId) ? null : (Id) input.contentDocumentId;

            if (String.isBlank(input.caseId)) {
                output.messageText = 'Please provide the dispute Case Id before uploading evidence.';
                outputs.add(output);
                continue;
            }

            if (contentDocumentId == null && contentVersionId != null) {
                ContentVersion versionRecord = [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :contentVersionId
                    LIMIT 1
                ];
                contentDocumentId = versionRecord.ContentDocumentId;
            } else if (contentVersionId == null && contentDocumentId != null) {
                ContentVersion versionRecord = [
                    SELECT Id
                    FROM ContentVersion
                    WHERE ContentDocumentId = :contentDocumentId
                    AND IsLatest = true
                    LIMIT 1
                ];
                contentVersionId = versionRecord.Id;
            }

            if (contentDocumentId == null || contentVersionId == null) {
                output.messageText = 'I could not find the uploaded bill file. Please upload the image again.';
                outputs.add(output);
                continue;
            }

            EinsteinOcrService.OcrResult ocrResult = EinsteinOcrService.extractBillData(contentVersionId);

            if ([
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocumentId
                AND LinkedEntityId = :input.caseId
            ] == 0) {
                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = contentDocumentId;
                link.LinkedEntityId = input.caseId;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                insert link;
            }

            Case disputeCase = new Case(
                Id = input.caseId,
                Evidence_Received__c = true,
                Evidence_Content_Document_Id__c = String.valueOf(contentDocumentId),
                Extracted_Bill_Data__c = ocrResult.extractedJson,
                Dispute_Stage__c = ocrResult.success ? 'Under Bank Review' : 'Evidence Received'
            );
            update disputeCase;

            output.success = true;
            output.evidenceReceived = true;
            output.ocrProcessed = ocrResult.success;
            output.contentDocumentId = String.valueOf(contentDocumentId);
            output.extractedDataJson = ocrResult.extractedJson;
            output.messageText = ocrResult.success
                ? 'Thanks, I received the bill photo, attached it to your dispute, and processed it with Einstein OCR. Your dispute is now under bank review.'
                : 'Thanks, I received the bill photo and attached it to your dispute. Einstein OCR setup needs attention, so the case is marked Evidence Received.';

            outputs.add(output);
        }

        return outputs;
    }
}
