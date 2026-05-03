public with sharing class GetDisputeStatusAction {
    public class ActionInput {
        @InvocableVariable public String accountId;
        @InvocableVariable public String mobileNumber;
        @InvocableVariable public String caseId;
    }

    public class ActionOutput {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String caseId;
        @InvocableVariable public String caseNumber;
        @InvocableVariable public Decimal disputeAmount;
        @InvocableVariable public String disputeStage;
        @InvocableVariable public Boolean provisionalCreditIssued;
        @InvocableVariable public Boolean evidenceReceived;
        @InvocableVariable public Date expectedResolutionDate;
        @InvocableVariable public String messageText;
    }

    @InvocableMethod(label='Get Dispute Status' description='Returns customer-friendly real-time status for a card dispute.')
    public static List<ActionOutput> getStatuses(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            output.success = false;

            Case disputeCase;
            if (String.isNotBlank(input.caseId)) {
                disputeCase = queryCaseById(input.caseId);
            } else {
                DisputeActionUtil.CustomerContext context = DisputeActionUtil.getVerifiedCustomer(input.accountId, input.mobileNumber);
                if (!context.isFound || !context.isVerified) {
                    output.messageText = context.message;
                    outputs.add(output);
                    continue;
                }
                disputeCase = queryLatestCase(context.account.Id);
            }

            if (disputeCase == null) {
                output.messageText = 'I could not find an active card dispute for this account.';
                outputs.add(output);
                continue;
            }

            output.success = true;
            output.caseId = disputeCase.Id;
            output.caseNumber = disputeCase.CaseNumber;
            output.disputeAmount = disputeCase.Dispute_Amount__c;
            output.disputeStage = disputeCase.Dispute_Stage__c;
            output.provisionalCreditIssued = disputeCase.Provisional_Credit_Issued__c;
            output.evidenceReceived = disputeCase.Evidence_Received__c;
            output.expectedResolutionDate = disputeCase.Expected_Resolution_Date__c;
            output.messageText =
                'Dispute ' + disputeCase.CaseNumber + ': ' + disputeCase.Dispute_Stage__c + '. ' +
                'Amount: ' + DisputeActionUtil.formatCurrency(disputeCase.Dispute_Amount__c) + '. ' +
                'Provisional credit: ' + (disputeCase.Provisional_Credit_Issued__c ? 'Issued' : 'Not issued yet') + '. ' +
                'Evidence: ' + (disputeCase.Evidence_Received__c ? 'Received' : 'Awaiting hotel bill photo') + '. ' +
                'Next update expected by ' + DisputeActionUtil.formatDate(disputeCase.Expected_Resolution_Date__c) + '.';

            outputs.add(output);
        }

        return outputs;
    }

    private static Case queryCaseById(String caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Dispute_Amount__c, Dispute_Stage__c,
                   Provisional_Credit_Issued__c, Evidence_Received__c,
                   Expected_Resolution_Date__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0];
    }

    private static Case queryLatestCase(Id accountId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Dispute_Amount__c, Dispute_Stage__c,
                   Provisional_Credit_Issued__c, Evidence_Received__c,
                   Expected_Resolution_Date__c
            FROM Case
            WHERE AccountId = :accountId
            AND Dispute_Amount__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0];
    }
}
