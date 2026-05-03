public with sharing class CreateCardDisputeAction {
    public class ActionInput {
        @InvocableVariable (label='Account ID' description='The Salesforce Account ID of the identified customer') public String accountId;
        @InvocableVariable (label='Mobile Number' description='The mobile number of the identified customer') public String mobileNumber;
        @InvocableVariable(required=true label='Financial Account Transaction ID' description='The ID of the financial account transaction') public String financialAccountTransactionId;
        @InvocableVariable (label='Customer Statement' description='The statement from the customer regarding the dispute') public String customerStatement;
        @InvocableVariable (label='Merchant or Location Hint' description='A hint about the merchant or location of the disputed transaction') public String merchantOrLocationHint;
    }

    public class ActionOutput {
        @InvocableVariable (label='Success' description='Indicates if the dispute was created successfully') public Boolean success;
        @InvocableVariable (label='Provisional Credit Issued' description='Indicates if a provisional credit was issued') public Boolean provisionalCreditIssued;
        @InvocableVariable (label='Case ID' description='The ID of the created case') public String caseId;
        @InvocableVariable (label='Case Number' description='The number of the created case') public String caseNumber;
        @InvocableVariable (label='Provisional Credit Transaction ID' description='The ID of the provisional credit transaction') public String provisionalCreditTransactionId;
        @InvocableVariable (label='Dispute Stage' description='The stage of the dispute') public String disputeStage;
        @InvocableVariable (label='Message Text' description='The message text for the output') public String messageText;
    }

    @InvocableMethod(label='Create Card Dispute' description='Creates a card dispute Case and issues a provisional credit.')
    public static List<ActionOutput> createDisputes(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            output.success = false;
            output.provisionalCreditIssued = false;

            DisputeActionUtil.CustomerContext context = DisputeActionUtil.getVerifiedCustomer(input.accountId, input.mobileNumber);
            if (!context.isFound || !context.isVerified) {
                output.messageText = context.message;
                outputs.add(output);
                continue;
            }

            if (String.isBlank(input.financialAccountTransactionId)) {
                output.messageText = 'Please identify the transaction before creating a dispute.';
                outputs.add(output);
                continue;
            }

            FinancialAccountTransaction disputedTxn = [
                SELECT Id, Amount, TransactionDate, Description, DebitCreditIndicator,
                       FinancialAccountId, FinancialAccount.Name, FinancialAccount.Type,
                       FinancialAccount.TotalOutstandingAmount
                FROM FinancialAccountTransaction
                WHERE Id = :input.financialAccountTransactionId
                LIMIT 1
            ];

            Case disputeCase = new Case();
            disputeCase.AccountId = context.account.Id;
            disputeCase.Subject = 'Unauthorized card transaction dispute - ' +
                DisputeActionUtil.formatCurrency(disputedTxn.Amount);
            disputeCase.Origin = DisputeActionUtil.picklistContains(Case.Origin, 'WhatsApp')
                ? 'WhatsApp'
                : 'Phone';
            disputeCase.Status = DisputeActionUtil.picklistContains(Case.Status, 'New')
                ? 'New'
                : Case.Status.getDescribe().getPicklistValues()[0].getValue();
            if (DisputeActionUtil.picklistContains(Case.Reason, 'Fraud')) {
                disputeCase.Reason = 'Fraud';
            }
            disputeCase.Description = input.customerStatement;
            disputeCase.Dispute_Amount__c = disputedTxn.Amount;
            disputeCase.Disputed_Transaction__c = disputedTxn.Id;
            disputeCase.Financial_Account__c = disputedTxn.FinancialAccountId;
            disputeCase.Dispute_Stage__c = 'Provisional Credit Issued';
            disputeCase.Provisional_Credit_Issued__c = true;
            disputeCase.Evidence_Received__c = false;
            disputeCase.Merchant_Location_Hint__c = input.merchantOrLocationHint;
            disputeCase.Customer_Statement__c = input.customerStatement;
            disputeCase.Expected_Resolution_Date__c = Date.today().addDays(2);
            disputeCase.Dispute_Match_Confidence__c = 95;
            insert disputeCase;

            disputeCase = [
                SELECT Id, CaseNumber, Dispute_Stage__c
                FROM Case
                WHERE Id = :disputeCase.Id
                LIMIT 1
            ];
            FinancialAccountTransaction provisionalCredit = createProvisionalCredit(disputedTxn, disputeCase.CaseNumber);

            disputeCase.Provisional_Credit_Transaction__c = provisionalCredit.Id;
            disputeCase.Dispute_Stage__c = 'Evidence Requested';
            update disputeCase;

            try {
                markTransactionDisputed(disputedTxn.Id);
                reduceOutstandingBalance(disputedTxn.FinancialAccountId, disputedTxn.Amount);
            } catch (Exception e) {
                System.debug('Non-blocking dispute relief update failed: ' + e.getMessage());
            }

            output.success = true;
            output.provisionalCreditIssued = true;
            output.caseId = disputeCase.Id;
            output.caseNumber = disputeCase.CaseNumber;
            output.provisionalCreditTransactionId = provisionalCredit.Id;
            output.disputeStage = disputeCase.Dispute_Stage__c;
            output.messageText =
                'I found the transaction "' + disputedTxn.Description + '" for ' +
                DisputeActionUtil.formatCurrency(disputedTxn.Amount) + '. ' +
                'I opened dispute ' + disputeCase.CaseNumber +
                ' and issued a provisional credit so you do not pay interest during the investigation. ' +
                'Please upload a clear photo of your hotel bill as your next WhatsApp message.';

            outputs.add(output);
        }

        return outputs;
    }

    private static FinancialAccountTransaction createProvisionalCredit(
        FinancialAccountTransaction disputedTxn,
        String caseNumber
    ) {
        FinancialAccountTransaction provisionalCredit = new FinancialAccountTransaction();
        provisionalCredit.FinancialAccountId = disputedTxn.FinancialAccountId;
        provisionalCredit.Amount = disputedTxn.Amount;
        provisionalCredit.TransactionDate = Date.today();
        provisionalCredit.DebitCreditIndicator = 'Credit';
        provisionalCredit.Description = 'Provisional credit for dispute ' + caseNumber;
        insert provisionalCredit;
        return provisionalCredit;
    }

    private static void markTransactionDisputed(Id transactionId) {
        FinancialAccountTransaction updateTxn = new FinancialAccountTransaction(Id = transactionId);
        DisputeActionUtil.setIfFieldExists(updateTxn, 'Is_Disputed__c', true);
        DisputeActionUtil.setIfFieldExists(updateTxn, 'Dispute_Status__c', 'Open');
        update updateTxn;
    }

    private static void reduceOutstandingBalance(Id financialAccountId, Decimal disputeAmount) {
        if (financialAccountId == null || disputeAmount == null) {
            return;
        }

        FinancialAccount accountToUpdate = [
            SELECT Id, TotalOutstandingAmount
            FROM FinancialAccount
            WHERE Id = :financialAccountId
            LIMIT 1
        ];

        if (accountToUpdate.TotalOutstandingAmount != null) {
            accountToUpdate.TotalOutstandingAmount = Math.max(0, accountToUpdate.TotalOutstandingAmount - disputeAmount);
            update accountToUpdate;
        }
    }
}
