public with sharing class GetDisputeStatusAction {
    public class ActionInput {
        @InvocableVariable (label='Account ID' description='The Salesforce Account ID of the identified customer') public String accountId;
        @InvocableVariable (label='Mobile Number' description='The mobile number of the identified customer') public String mobileNumber;
        @InvocableVariable (label='Case ID' description='The ID of the dispute Case') public String caseId;
        @InvocableVariable (label='Selection Number' description='The customer selected dispute number from the previous list') public Integer selectionNumber;
    }

    public class ActionOutput {
        @InvocableVariable (label='Success' description='Indicates if the operation was successful') public Boolean success;
        @InvocableVariable (label='Case ID' description='The ID of the dispute Case') public String caseId;
        @InvocableVariable (label='Case Number' description='The number of the dispute Case') public String caseNumber;
        @InvocableVariable (label='Dispute Amount' description='The amount of the dispute') public Decimal disputeAmount;
        @InvocableVariable (label='Dispute Stage' description='The current stage of the dispute') public String disputeStage;
        @InvocableVariable (label='Provisional Credit Issued' description='Indicates if provisional credit has been issued') public Boolean provisionalCreditIssued;
        @InvocableVariable (label='Evidence Received' description='Indicates if evidence has been received') public Boolean evidenceReceived;
        @InvocableVariable (label='Expected Resolution Date' description='The date by which the dispute is expected to be resolved') public Date expectedResolutionDate;
        @InvocableVariable (label='Is Verified' description='Indicates if the customer is verified') public Boolean isVerified;
        @InvocableVariable (label='Dispute Count' description='Number of active dispute cases found') public Integer disputeCount;
        @InvocableVariable (label='Needs Selection' description='Indicates if the customer needs to select a dispute') public Boolean needsSelection;
        @InvocableVariable (label='Candidate Disputes JSON' description='JSON list of active disputes for customer selection') public String candidateDisputesJson;
        @InvocableVariable (label='Message Text' description='The message text for the output') public String messageText;
    }

    private class CandidateDispute {
        public Integer selectionNumber;
        public String caseId;
        public String caseNumber;
        public Decimal disputeAmount;
        public String disputeStage;
        public String merchantOrLocationHint;
        public Date expectedResolutionDate;
    }

    @InvocableMethod(label='Get Dispute Status' description='Returns customer-friendly real-time status for a card dispute.')
    public static List<ActionOutput> getStatuses(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            output.success = false;
            output.needsSelection = false;
            output.disputeCount = 0;

            Case disputeCase;
            if (String.isNotBlank(input.caseId)) {
                disputeCase = queryCaseById(input.caseId);
            } else {
                DisputeActionUtil.CustomerContext context = DisputeActionUtil.getVerifiedCustomer(input.accountId, input.mobileNumber);
                if (!context.isFound || !context.isVerified) {
                    output.messageText = context.message;
                    output.isVerified = context.isVerified;
                    outputs.add(output);
                    continue;
                }

                List<Case> activeDisputes = queryActiveDisputes(context.account.Id);
                output.disputeCount = activeDisputes.size();
                output.candidateDisputesJson = JSON.serialize(buildCandidates(activeDisputes));

                if (activeDisputes.isEmpty()) {
                    output.messageText = 'I could not find an active card dispute for this account.';
                    outputs.add(output);
                    continue;
                }

                if (input.selectionNumber != null) {
                    if (input.selectionNumber < 1 || input.selectionNumber > activeDisputes.size()) {
                        output.needsSelection = true;
                        output.messageText = buildSelectionMessage(activeDisputes, 'Please reply with a valid dispute number from the list below.');
                        outputs.add(output);
                        continue;
                    }

                    disputeCase = activeDisputes[input.selectionNumber - 1];
                } else if (activeDisputes.size() == 1) {
                    disputeCase = activeDisputes[0];
                } else {
                    output.needsSelection = true;
                    output.messageText = buildSelectionMessage(activeDisputes, 'I found multiple active disputes. Please reply with the number you want to check.');
                    outputs.add(output);
                    continue;
                }
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
            output.disputeCount = output.disputeCount == 0 ? 1 : output.disputeCount;
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

    private static List<Case> queryActiveDisputes(Id accountId) {
        return [
            SELECT Id, CaseNumber, Dispute_Amount__c, Dispute_Stage__c,
                   Provisional_Credit_Issued__c, Evidence_Received__c,
                   Expected_Resolution_Date__c, Merchant_Location_Hint__c
            FROM Case
            WHERE AccountId = :accountId
            AND Dispute_Amount__c != null
            AND (IsClosed = false OR Dispute_Stage__c NOT IN ('Resolved - Customer Credited', 'Rejected'))
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
    }

    private static List<CandidateDispute> buildCandidates(List<Case> activeDisputes) {
        List<CandidateDispute> candidates = new List<CandidateDispute>();
        Integer index = 1;

        for (Case disputeCase : activeDisputes) {
            CandidateDispute candidate = new CandidateDispute();
            candidate.selectionNumber = index;
            candidate.caseId = disputeCase.Id;
            candidate.caseNumber = disputeCase.CaseNumber;
            candidate.disputeAmount = disputeCase.Dispute_Amount__c;
            candidate.disputeStage = disputeCase.Dispute_Stage__c;
            candidate.merchantOrLocationHint = disputeCase.Merchant_Location_Hint__c;
            candidate.expectedResolutionDate = disputeCase.Expected_Resolution_Date__c;
            candidates.add(candidate);
            index++;
        }

        return candidates;
    }

    private static String buildSelectionMessage(List<Case> activeDisputes, String heading) {
        List<String> lines = new List<String>{ heading, '' };
        Integer index = 1;

        for (Case disputeCase : activeDisputes) {
            String merchantHint = String.isBlank(disputeCase.Merchant_Location_Hint__c)
                ? 'Card dispute'
                : disputeCase.Merchant_Location_Hint__c;
            lines.add(
                String.valueOf(index) + '. ' +
                disputeCase.CaseNumber + ' - ' +
                DisputeActionUtil.formatCurrency(disputeCase.Dispute_Amount__c) + ' - ' +
                disputeCase.Dispute_Stage__c + ' - ' +
                merchantHint
            );
            index++;
        }

        return String.join(lines, '\n');
    }
}
