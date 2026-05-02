public class GetBankingDetailsAction {
    
    public class ActionInput {
        @InvocableVariable(required=true description='The 10-digit mobile number provided by the user')
        public String mobileNumber;
    }

    public class ActionOutputouter {
        @InvocableVariable public ActionOutput actionRes;
    }
    
    public class ActionOutput {
        @InvocableVariable public String accountId;
        @InvocableVariable public Boolean isVerified; 
        @InvocableVariable public String customerName;
        @InvocableVariable public String maskedPhone;
        @InvocableVariable public String churnRisk;
        @InvocableVariable public String preferredLanguage;
        @InvocableVariable public Decimal checkingBalance;
        @InvocableVariable public Decimal creditCardBalance;
        @InvocableVariable public Decimal loanOutstanding;
        @InvocableVariable public String transactionsJson;
        
        // NEW: Dynamic message to guide the Agent and User
        @InvocableVariable public String statusMessage; 
    }

    @InvocableMethod(label='Get Customer 360 and Mini Statement' description='Authenticates user and fetches full profile.')
    public static List<ActionOutputouter> getBankingDetails(List<ActionInput> inputs) {
        
        List<ActionOutputouter> finalOutputs = new List<ActionOutputouter>();
        
        for (ActionInput input : inputs) {
            
            ActionOutputouter outerResult = new ActionOutputouter();
            ActionOutput innerData = new ActionOutput();
            
            try {
                // 1. Find Customer by Phone
                Account acc = [SELECT Id, Name, Phone, Is_Session_Verified__c, Churn_Risk_Level__c, Preferred_Language__c 
                               FROM Account 
                               WHERE Phone = :input.mobileNumber LIMIT 1];
                
                innerData.accountId = acc.Id;
                innerData.customerName = acc.Name;
                innerData.isVerified = acc.Is_Session_Verified__c;
                innerData.maskedPhone = '******' + input.mobileNumber.right(4);
                innerData.churnRisk = acc.Churn_Risk_Level__c != null ? acc.Churn_Risk_Level__c : 'Low';
                innerData.preferredLanguage = acc.Preferred_Language__c != null ? acc.Preferred_Language__c : 'English';
                
                // --- NEW: Dynamic Messaging Logic ---
                if (innerData.isVerified == true) {
                    innerData.statusMessage = 'Session is already verified. Retrieving the 360-degree banking profile and recent transactions for ' + acc.Name + '.';
                } else {
                    innerData.statusMessage = 'Please complete the secure verification for your registered mobile number (' + innerData.maskedPhone + ') in the widget below to access your banking details.';
                }
                
                // 2. Fetch Financial Accounts 
                List<FinancialAccount> allAccounts = [SELECT Type, Current_Balance__c, TotalOutstandingAmount 
                                                      FROM FinancialAccount 
                                                      WHERE Primary_Owner__c = :acc.Id];
                
                innerData.checkingBalance = 0.00;
                innerData.creditCardBalance = 0.00;
                innerData.loanOutstanding = 0.00;
                
                for (FinancialAccount fa : allAccounts) {
                    if (fa.Type == 'Checking') {
                        innerData.checkingBalance = fa.Current_Balance__c;
                    } else if (fa.Type == 'Credit Card') {
                        innerData.creditCardBalance = fa.TotalOutstandingAmount; 
                    } else if (fa.Type == 'Mortgage' || fa.Type == 'Loan') {
                        innerData.loanOutstanding = fa.TotalOutstandingAmount; 
                    }
                }
                
                // 3. Fetch Transactions
                List<FinancialAccountTransaction> transactions = [SELECT Id, Amount, TransactionDate, Description, Type 
                                                                  FROM FinancialAccountTransaction 
                                                                  WHERE FinancialAccount.Primary_Owner__c = :acc.Id 
                                                                  ORDER BY TransactionDate DESC LIMIT 5];
                
                innerData.transactionsJson = JSON.serialize(transactions);
                
            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
                // --- NEW: Error Messaging ---
                innerData.isVerified = false;
                innerData.statusMessage = 'I could not find a customer profile linked to the mobile number ' + input.mobileNumber + '. Please check the number and try again.';
            }
            
            outerResult.actionRes = innerData;
            finalOutputs.add(outerResult);
        }
        
        return finalOutputs;
    }
}
