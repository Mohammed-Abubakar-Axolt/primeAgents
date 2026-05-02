public class GetBankingDetailsAction {
    
    public class ActionInput {
        @InvocableVariable(required=true description='The 10-digit mobile number provided by the user')
        public String mobileNumber;
    }

    public class ActionOutputouter {
        @AuraEnabled @InvocableVariable public ActionOutput actionRes;
    }
    
    public class ActionOutput {
        @AuraEnabled @InvocableVariable public String accountId;
        @AuraEnabled @InvocableVariable public Boolean isFound;
        @AuraEnabled @InvocableVariable public Boolean isVerified; 
        @AuraEnabled @InvocableVariable public String customerName;
        @AuraEnabled @InvocableVariable public String maskedPhone;
        @AuraEnabled @InvocableVariable public String churnRisk;
        @AuraEnabled @InvocableVariable public String preferredLanguage;
        @AuraEnabled @InvocableVariable public Decimal checkingBalance;
        @AuraEnabled @InvocableVariable public Decimal creditCardBalance;
        @AuraEnabled @InvocableVariable public Decimal loanOutstanding;
        @AuraEnabled @InvocableVariable public String transactionsJson;
        
        // NEW: Dynamic message to guide the Agent and User
        @AuraEnabled @InvocableVariable public String statusMessage; 
    }

    @InvocableMethod(label='Get Customer 360 and Mini Statement' description='Authenticates user and fetches full profile.')
    public static List<ActionOutputouter> getBankingDetails(List<ActionInput> inputs) {
        
        List<ActionOutputouter> finalOutputs = new List<ActionOutputouter>();
        
        for (ActionInput input : inputs) {
            
            ActionOutputouter outerResult = new ActionOutputouter();
            ActionOutput innerData = new ActionOutput();
            
            try {
                List<Account> accounts = [
                    SELECT Id, Name, Phone, Is_Session_Verified__c, Preferred_Language__c
                    FROM Account
                    WHERE Phone = :input.mobileNumber
                    LIMIT 1
                ];

                if (accounts.isEmpty()) {
                    innerData.isFound = false;
                    innerData.isVerified = false;
                    innerData.maskedPhone = maskPhone(input.mobileNumber);
                    innerData.statusMessage = 'No account was found for this mobile number. Please check the number and re-enter it in the chat.';
                    outerResult.actionRes = innerData;
                    finalOutputs.add(outerResult);
                    continue;
                }

                Account acc = accounts[0];
                
                innerData.accountId = acc.Id;
                innerData.isFound = true;
                innerData.isVerified = acc.Is_Session_Verified__c;
                innerData.maskedPhone = maskPhone(acc.Phone);
                
                // --- NEW: Dynamic Messaging Logic ---
                if (innerData.isVerified == true) {
                    populateVerifiedDetails(innerData, acc);
                    innerData.statusMessage = 'Session is already verified. Retrieving the 360-degree banking profile and recent transactions for ' + acc.Name + '.';
                } else {
                    innerData.statusMessage = 'Please complete the secure verification for your registered mobile number (' + innerData.maskedPhone + ') in the widget below to access your banking details.';
                }
                
            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
                // --- NEW: Error Messaging ---
                innerData.isFound = false;
                innerData.isVerified = false;
                innerData.maskedPhone = maskPhone(input.mobileNumber);
                innerData.statusMessage = 'No account was found for this mobile number. Please check the number and re-enter it in the chat.';
            }
            
            outerResult.actionRes = innerData;
            finalOutputs.add(outerResult);
        }
        
        return finalOutputs;
    }

    @AuraEnabled
    public static ActionOutput getVerifiedBankingDetails(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account Id is missing. Banking details could not be loaded.');
        }

        Account acc = [
            SELECT Id, Name, Phone, Is_Session_Verified__c, Preferred_Language__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (acc.Is_Session_Verified__c != true) {
            throw new AuraHandledException('Verification is not complete. Please verify the OTP before viewing banking details.');
        }

        ActionOutput output = new ActionOutput();
        output.accountId = acc.Id;
        output.isFound = true;
        output.isVerified = true;
        output.maskedPhone = maskPhone(acc.Phone);
        populateVerifiedDetails(output, acc);
        output.statusMessage = 'Verification complete. Banking details refreshed.';

        return output;
    }

    private static void populateVerifiedDetails(ActionOutput output, Account acc) {
        output.customerName = acc.Name;
        output.preferredLanguage = acc.Preferred_Language__c != null ? acc.Preferred_Language__c : 'English';
        output.churnRisk = null;

        List<FinancialAccount> allAccounts = [
            SELECT Type, Current_Balance__c, TotalOutstandingAmount
            FROM FinancialAccount
            WHERE Primary_Owner__c = :acc.Id
        ];

        output.checkingBalance = 0.00;
        output.creditCardBalance = 0.00;
        output.loanOutstanding = 0.00;

        for (FinancialAccount fa : allAccounts) {
            if (fa.Type == 'Checking' || fa.Type == 'Checking Account' || fa.Type == 'Bank Account') {
                output.checkingBalance = fa.Current_Balance__c;
            } else if (fa.Type == 'Credit Card') {
                output.creditCardBalance = fa.TotalOutstandingAmount;
            } else if (fa.Type == 'Mortgage' || fa.Type == 'Loan') {
                output.loanOutstanding = fa.TotalOutstandingAmount;
            }
        }

        List<FinancialAccountTransaction> transactions = [
            SELECT Id, Amount, TransactionDate, Description, Type
            FROM FinancialAccountTransaction
            WHERE FinancialAccount.Primary_Owner__c = :acc.Id
            ORDER BY TransactionDate DESC
            LIMIT 5
        ];

        output.transactionsJson = JSON.serialize(transactions);
    }

    private static String maskPhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) {
            return '';
        }

        String trimmedPhone = phoneNumber.trim();
        Integer visibleDigits = Math.min(4, trimmedPhone.length());
        return '******' + trimmedPhone.right(visibleDigits);
    }
}
