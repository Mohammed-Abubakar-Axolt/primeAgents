public class IdentifyCustomerAction {
    
    public class ActionInput {
        @InvocableVariable(required=true label='Mobile Number' description='The 10-digit mobile number provided by the user')
        public String mobileNumber;
    }
    
    public class ActionOutput {
        @InvocableVariable (label='Customer Account ID' description='The Salesforce Account ID of the identified customer') public String accountId;
        @InvocableVariable (label='Customer Name' description='The name of the identified customer') public String customerName;
        @InvocableVariable (label='Masked Phone' description='The phone number with all but the last four digits masked') public String maskedPhone;
        @InvocableVariable (label='Is Found' description='Indicates whether the customer was found') public Boolean isFound;
    }

    @InvocableMethod(label='Identify Customer by Phone' description='Finds a customer by phone and initializes the verification widget.')
    public static List<ActionOutput> identifyCustomer(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();
        
        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            
            try {
                // Find the Person Account by Phone
                Account acc = [SELECT Id, Name, Phone FROM Account WHERE Phone = :input.mobileNumber LIMIT 1];
                
                output.accountId = acc.Id;
                output.customerName = acc.Name;
                output.isFound = true;
                // Mask phone: show only last 4 digits
                output.maskedPhone = '******' + input.mobileNumber.right(4); 
                
                // Reset verification status for a new session
                acc.Is_Session_Verified__c = false;
                update acc;
                
            } catch (Exception e) {
                output.isFound = false;
                output.customerName = 'Not Found';
            }
            outputs.add(output);
        }
        return outputs;
    }

    @AuraEnabled
    public static String generateAndSendOtp(String accountId) {
        // 1. Fetch the user's actual phone number from the database
        Account acc = [SELECT Id, Phone FROM Account WHERE Id = :accountId LIMIT 1];
        
        // 2. Generate the random 4-digit code
        Integer randomNum = Math.round(Math.random() * 8999) + 1000; 
        String otpCode = String.valueOf(randomNum);
        
        // 3. Construct the message
        String message = 'Your secure banking OTP is: ' + otpCode + '. Do not share this with anyone.';
        
        // 4. Fire the real SMS via Twilio if the phone number exists
        if (String.isNotBlank(acc.Phone)) {
            TwilioService.sendSMS(acc.Phone, message);
        }
        
        // 5. Return the code back to the LWC so it can validate what the user types
        return otpCode; 
    }
    
    @AuraEnabled
    public static void setSessionVerified(String accountId) {
        Account acc = new Account(Id = accountId, Is_Session_Verified__c = true);
        update acc;
    }
}