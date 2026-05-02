public class GetBankingDetailsAction {
    
    // INPUT WRAPPER
    public class ActionInput {
        @InvocableVariable(required=true description='Type of account the user is asking about (e.g., Checking Account, Credit Card)')
        public String accountType;
    }
    
    // OUTPUT WRAPPER
    public class ActionOutput {
        @InvocableVariable(description='The name of the Financial Account')
        public String accountName;
        
        @InvocableVariable(description='The current balance of the account')
        public Decimal currentBalance;
        
        @InvocableVariable(description='JSON string containing the last 5 transactions')
        public String transactionsJson;
    }

    @InvocableMethod(label='Get Balance and Mini Statement' description='Fetches the current balance and recent transactions for a specified account type.')
    public static List<ActionOutput> getBankingDetails(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();
        
        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            
            try {
                // Hackathon Strategy: We query Rajesh's specific account based on the type requested by the Agent
                // Note: Ensure your object API names match your org (FinancialAccount or FinServ__FinancialAccount__c)
                FinancialAccount account = [SELECT Id, Name, Current_Balance__c 
                                            FROM FinancialAccount 
                                            WHERE Type = :input.accountType 
                                            LIMIT 1];
                
                output.accountName = account.Name;
                output.currentBalance = account.Current_Balance__c;
                
                // Fetch the 5 recent transactions we created
                List<FinancialAccountTransaction> transactions = [SELECT Id, Amount, TransactionDate, Description, Type 
                                                                  FROM FinancialAccountTransaction 
                                                                  WHERE FinancialAccountId = :account.Id 
                                                                  ORDER BY TransactionDate DESC 
                                                                  LIMIT 5];
                
                // Serialize transactions to JSON to easily pass to the LWC Renderer
                output.transactionsJson = JSON.serialize(transactions);
                
            } catch (Exception e) {
                // Failsafe for the demo if the query misses
                output.accountName = 'Account Not Found';
                output.currentBalance = 0.00;
                output.transactionsJson = '[]';
            }
            
            outputs.add(output);
        }
        
        return outputs;
    }
}