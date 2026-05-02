public class GetBankingDetailsAction {
    
    public class ActionInput {
        @InvocableVariable(required=true description='The 10-digit mobile number provided by the user')
        public String mobileNumber;
    }
    
    public class ActionOutput {
        @InvocableVariable public String accountId;
        @InvocableVariable public Boolean isVerified; // Tells the LWC which screen to show
        @InvocableVariable public String customerName;
        @InvocableVariable public String maskedPhone;
        @InvocableVariable public String churnRisk;
        @InvocableVariable public String preferredLanguage;
        @InvocableVariable public Decimal checkingBalance;
        @InvocableVariable public Decimal creditCardBalance;
        @InvocableVariable public Decimal loanOutstanding;
        @InvocableVariable public String transactionsJson;
    }

    @InvocableMethod(label='Get Customer 360 and Mini Statement' description='Authenticates user and fetches full profile.')
    public static List<ActionOutput> getBankingDetails(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();
        
        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            
            try {
                // 1. Find Customer by Phone
                Account acc = [SELECT Id, Name, Phone, Is_Session_Verified__c, Churn_Risk_Level__c, Preferred_Language__c 
                               FROM Account 
                               WHERE Phone = :input.mobileNumber LIMIT 1];
                
                output.accountId = acc.Id;
                output.customerName = acc.Name;
                output.isVerified = acc.Is_Session_Verified__c;
                output.maskedPhone = '******' + input.mobileNumber.right(4);
                output.churnRisk = acc.Churn_Risk_Level__c != null ? acc.Churn_Risk_Level__c : 'Low';
                output.preferredLanguage = acc.Preferred_Language__c != null ? acc.Preferred_Language__c : 'English';
                
                // 2. Fetch Financial Accounts (FIXED SOQL)
                List<FinancialAccount> allAccounts = [SELECT Type, Current_Balance__c, TotalOutstandingAmount 
                                                      FROM FinancialAccount 
                                                      WHERE Primary_Owner__c = :acc.Id];
                
                output.checkingBalance = 0.00;
                output.creditCardBalance = 0.00;
                output.loanOutstanding = 0.00;
                
                for (FinancialAccount fa : allAccounts) {
                    if (fa.Type == 'Checking Account' || fa.Type == 'Bank Account') {
                        output.checkingBalance = fa.Current_Balance__c;
                    } else if (fa.Type == 'Credit Card') {
                        output.creditCardBalance = fa.TotalOutstandingAmount; // FIXED
                    } else if (fa.Type == 'Mortgage' || fa.Type == 'Loan') {
                        output.loanOutstanding = fa.TotalOutstandingAmount; // FIXED
                    }
                }
                
                // 3. Fetch Transactions
                List<FinancialAccountTransaction> transactions = [SELECT Id, Amount, TransactionDate, Description, Type 
                                                                  FROM FinancialAccountTransaction 
                                                                  WHERE FinancialAccount.Primary_Owner__c = :acc.Id 
                                                                  AND FinancialAccount.Type IN ('Checking Account', 'Bank Account')
                                                                  ORDER BY TransactionDate DESC LIMIT 5];
                
                output.transactionsJson = JSON.serialize(transactions);
                
            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
                // If phone not found, leave isVerified null/false
            }
            outputs.add(output);
        }
        return outputs;
    }
}