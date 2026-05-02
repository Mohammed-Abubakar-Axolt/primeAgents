public class GetBankingDetailsAction {
    
    // INPUT: Now requires the Account ID from the verified session
    public class ActionInput {
        @InvocableVariable(required=true description='The Salesforce ID of the verified Account')
        public String accountId;
        
        @InvocableVariable(required=false description='Specific account type requested (e.g., Checking Account)')
        public String accountType;
    }
    
    // OUTPUT: Expanded to include full 360-degree customer details
    public class ActionOutput {
        @InvocableVariable public String customerName;
        @InvocableVariable public String churnRisk;
        @InvocableVariable public String preferredLanguage;
        @InvocableVariable public Decimal checkingBalance;
        @InvocableVariable public Decimal creditCardBalance;
        @InvocableVariable public Decimal loanOutstanding;
        @InvocableVariable public String transactionsJson;
    }

    @InvocableMethod(label='Get Customer 360 and Mini Statement' description='Fetches the full customer profile, all account balances, and recent transactions.')
    public static List<ActionOutput> getBankingDetails(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();
        
        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            
            try {
                // 1. Fetch the 360 Customer Profile
                Account acc = [SELECT Id, Name, Churn_Risk_Level__c, Preferred_Language__c 
                               FROM Account 
                               WHERE Id = :input.accountId LIMIT 1];
                
                output.customerName = acc.Name;
                output.churnRisk = acc.Churn_Risk_Level__c != null ? acc.Churn_Risk_Level__c : 'Low';
                output.preferredLanguage = acc.Preferred_Language__c != null ? acc.Preferred_Language__c : 'English';
                
                // 2. Fetch ALL Financial Accounts to build the 360 View
                // Note: Using the custom lookup Primary_Owner__c we built earlier
                List<FinancialAccount> allAccounts = [SELECT Type, Current_Balance__c, TotalOutstandingAmount__c 
                                                      FROM FinancialAccount 
                                                      WHERE Primary_Owner__c = :input.accountId];
                
                // Initialize balances
                output.checkingBalance = 0.00;
                output.creditCardBalance = 0.00;
                output.loanOutstanding = 0.00;
                
                // Sort balances by type
                for (FinancialAccount fa : allAccounts) {
                    if (fa.Type == 'Checking Account' || fa.Type == 'Bank Account') {
                        output.checkingBalance = fa.Current_Balance__c;
                    } else if (fa.Type == 'Credit Card') {
                        output.creditCardBalance = fa.TotalOutstandingAmount__c; // Amount owed
                    } else if (fa.Type == 'Mortgage' || fa.Type == 'Loan') {
                        output.loanOutstanding = fa.TotalOutstandingAmount__c;
                    }
                }
                
                // 3. Fetch the recent transactions (defaulting to Checking for Scenario 1)
                List<FinancialAccountTransaction> transactions = [SELECT Id, Amount, TransactionDate, Description, Type 
                                                                  FROM FinancialAccountTransaction 
                                                                  WHERE FinancialAccount.Primary_Owner__c = :input.accountId 
                                                                  AND FinancialAccount.Type IN ('Checking Account', 'Bank Account')
                                                                  ORDER BY TransactionDate DESC 
                                                                  LIMIT 5];
                
                output.transactionsJson = JSON.serialize(transactions);
                
            } catch (Exception e) {
                System.debug('Error in 360 fetch: ' + e.getMessage());
            }
            
            outputs.add(output);
        }
        return outputs;
    }
}