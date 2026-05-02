public class IdentifyCustomerAction {
    public class OtpResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean alreadyVerified;
        @AuraEnabled public String otpCode;
        @AuraEnabled public String message;
    }

    
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
                Account acc = [
                    SELECT Id, Name, Phone, Is_Session_Verified__c
                    FROM Account
                    WHERE Phone = :input.mobileNumber
                    LIMIT 1
                ];
                
                output.accountId = acc.Id;
                output.customerName = acc.Name;
                output.isFound = true;
                output.maskedPhone = '******' + input.mobileNumber.right(4); 
                
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
        OtpResult result = generateAndSendOtpWithStatus(accountId);
        if (result.success != true) {
            throw new AuraHandledException(result.message);
        }

        return result.otpCode;
    }

    @AuraEnabled
    public static OtpResult generateAndSendOtpWithStatus(String accountId) {
        OtpResult result = new OtpResult();
        result.success = false;
        result.alreadyVerified = false;

        System.debug('--- STARTING OTP GENERATION ---');
        System.debug('1. Received Account ID: ' + accountId);

        if (String.isBlank(accountId)) {
            result.message = 'Account Id is missing. OTP was not sent.';
            return result;
        }
        
        Account acc = [
            SELECT Id, Phone, Is_Session_Verified__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        System.debug('2. Fetched Phone Number from DB: ' + acc.Phone);

        if (acc.Is_Session_Verified__c == true) {
            result.success = true;
            result.alreadyVerified = true;
            result.message = 'Session is already verified. OTP was not sent.';
            System.debug('3. Session already verified. Skipping OTP generation and Twilio callout.');
            return result;
        }

        if (String.isBlank(acc.Phone)) {
            System.debug('4. ERROR: Phone number is blank on the Account record! SMS aborted.');
            result.message = 'No registered phone number was found for this customer.';
            return result;
        }
        
        Integer randomNum = Math.round(Math.random() * 8999) + 1000; 
        String otpCode = String.valueOf(randomNum);
        System.debug('3. Generated Demo OTP: ' + otpCode);
        
        String message = 'Your secure banking OTP is: ' + otpCode + '. Do not share this with anyone.';
        
        System.debug('4. Phone is not blank. Initiating Twilio Service...');
        TwilioService.SmsResult smsResult = TwilioService.sendSMS(acc.Phone, message);

        result.success = smsResult.success;
        result.message = smsResult.message;

        if (smsResult.success == true) {
            result.otpCode = otpCode;
        } else {
            System.debug('5. ERROR: Twilio could not send OTP. ' + smsResult.message);
        }
        
        return result; 
    }
    
    @AuraEnabled
    public static Boolean setSessionVerified(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account Id is missing. Session could not be verified.');
        }

        Account acc = new Account(Id = accountId, Is_Session_Verified__c = true);
        update acc;

        System.debug('Session verified for Account ID: ' + accountId);

        Account verifiedAccount = [
            SELECT Is_Session_Verified__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (verifiedAccount.Is_Session_Verified__c != true) {
            throw new AuraHandledException('Session verification did not persist on the Account record.');
        }

        return true;
    }
}
