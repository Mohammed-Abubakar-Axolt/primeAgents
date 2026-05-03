public class IdentifyCustomerAction {
    public class OtpResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean alreadyVerified;
        @AuraEnabled public String otpCode;
        @AuraEnabled public String message;
    }

    public class ActionInput {
        @InvocableVariable(label='Mobile Number' description='The 10-digit mobile number provided by the user')
        public String mobileNumber;

        @InvocableVariable(label='OTP Code' description='OTP entered by the customer')
        public String otpCode;

        @InvocableVariable(label='Mode' description='send_otp, verify_otp, resend_otp, edit_mobile')
        public String mode;

        @InvocableVariable(label='Is Resend OTP' description='True when the customer asks to resend OTP')
        public Boolean isResendOtp;

        @InvocableVariable(label='Is Mobile Number Edit' description='True when the customer wants to edit or re-enter mobile number')
        public Boolean isMobileNumberEdit;
    }
    
    public class ActionOutput {
        @InvocableVariable (label='Customer Account ID' description='The Salesforce Account ID of the identified customer') public String accountId;
        @InvocableVariable (label='Customer Name' description='The name of the identified customer') public String customerName;
        @InvocableVariable (label='Masked Phone' description='The phone number with all but the last four digits masked') public String maskedPhone;
        @InvocableVariable (label='Is Found' description='Indicates whether the customer was found') public Boolean isFound;
        @InvocableVariable (label='Is Customer Verified' description='Indicates whether the customer session is verified') public Boolean isCustomerVerified;
        @InvocableVariable (label='OTP Sent' description='Indicates whether OTP was sent successfully') public Boolean otpSent;
        @InvocableVariable (label='Needs OTP' description='Indicates whether the customer should enter an OTP') public Boolean needsOtp;
        @InvocableVariable (label='Needs Mobile Number' description='Indicates whether the customer should enter or re-enter a mobile number') public Boolean needsMobileNumber;
        @InvocableVariable (label='Message Text' description='Customer-facing WhatsApp-safe message') public String messageText;
    }

    @InvocableMethod(label='Identify Customer by Phone' description='Finds a customer by phone and initializes the verification widget.')
    public static List<ActionOutput> identifyCustomer(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();
        
        for (ActionInput input : inputs) {
            outputs.add(handleTextVerification(input));
        }
        return outputs;
    }

    private static ActionOutput handleTextVerification(ActionInput input) {
        ActionOutput output = baseOutput();
        String mode = normalizeMode(input);

        if (mode == 'edit_mobile') {
            output.needsMobileNumber = true;
            output.messageText = 'Sure. Please re-enter your registered 10-digit mobile number.';
            return output;
        }

        if (String.isBlank(input.mobileNumber)) {
            output.needsMobileNumber = true;
            output.messageText = 'Please enter your registered 10-digit mobile number to continue.';
            return output;
        }

        List<Account> accounts = [
            SELECT Id, Name, Phone, Is_Session_Verified__c, Current_Session_OTP__c
            FROM Account
            WHERE Phone = :input.mobileNumber
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            output.needsMobileNumber = true;
            output.messageText = 'I could not find an account linked with this mobile number. Please check the number and re-enter it in the chat.';
            return output;
        }

        Account acc = accounts[0];
        populateCustomer(output, acc);

        if (acc.Is_Session_Verified__c == true) {
            output.isCustomerVerified = true;
            output.needsOtp = false;
            output.messageText = 'Your session is already verified. You can continue with your card dispute.';
            return output;
        }

        if (mode == 'verify_otp') {
            return verifyStoredOtp(output, acc, input.otpCode);
        }

        return sendAndStoreOtp(output, acc, mode == 'resend_otp');
    }

    private static ActionOutput baseOutput() {
        ActionOutput output = new ActionOutput();
        output.isFound = false;
        output.isCustomerVerified = false;
        output.otpSent = false;
        output.needsOtp = false;
        output.needsMobileNumber = false;
        return output;
    }

    private static String normalizeMode(ActionInput input) {
        if (input != null && input.isMobileNumberEdit == true) {
            return 'edit_mobile';
        }
        if (input != null && input.isResendOtp == true) {
            return 'resend_otp';
        }
        if (input != null && String.isNotBlank(input.mode)) {
            return input.mode.trim().toLowerCase();
        }
        if (input != null && String.isNotBlank(input.otpCode)) {
            return 'verify_otp';
        }
        return 'send_otp';
    }

    private static void populateCustomer(ActionOutput output, Account acc) {
        output.accountId = acc.Id;
        output.customerName = acc.Name;
        output.isFound = true;
        output.maskedPhone = maskPhone(acc.Phone);
    }

    private static ActionOutput verifyStoredOtp(ActionOutput output, Account acc, String otpCode) {
        if (String.isBlank(otpCode)) {
            output.needsOtp = true;
            output.messageText = 'Please enter the OTP sent to ' + output.maskedPhone + '. If you did not receive it, would you like me to resend the OTP or edit the mobile number?';
            return output;
        }

        if (String.isBlank(acc.Current_Session_OTP__c)) {
            output.needsOtp = true;
            output.messageText = 'I could not find an active OTP for this session. Would you like me to resend the OTP or edit the mobile number?';
            return output;
        }

        if (otpCode.trim() == acc.Current_Session_OTP__c) {
            Account updateAccount = new Account(
                Id = acc.Id,
                Is_Session_Verified__c = true,
                Current_Session_OTP__c = null
            );
            update updateAccount;

            output.isCustomerVerified = true;
            output.needsOtp = false;
            output.messageText = 'OTP verified successfully. Your session is now verified, and you can continue with your card dispute.';
        } else {
            output.needsOtp = true;
            output.messageText = 'The OTP you entered is incorrect. Please try again. If you did not receive the OTP, would you like me to resend it or edit the mobile number?';
        }

        return output;
    }

    private static ActionOutput sendAndStoreOtp(ActionOutput output, Account acc, Boolean isResend) {
        if (String.isBlank(acc.Phone)) {
            output.needsMobileNumber = true;
            output.messageText = 'No registered mobile number was found for this customer. Please re-enter the mobile number in chat.';
            return output;
        }

        String otpCode = generateOtpCode();
        TwilioService.SmsResult smsResult = TwilioService.sendSMS(
            acc.Phone,
            'Your secure banking OTP is: ' + otpCode + '. Do not share this with anyone.'
        );

        if (smsResult.success == true) {
            update new Account(Id = acc.Id, Current_Session_OTP__c = otpCode);

            output.otpSent = true;
            output.needsOtp = true;
            output.messageText = (isResend ? 'I resent' : 'I sent') +
                ' a secure OTP to your registered mobile number ' + output.maskedPhone +
                '. Please enter the OTP here. If you did not receive it, would you like me to resend the OTP or edit the mobile number?';
        } else {
            output.needsOtp = false;
            output.messageText = 'I could not send the OTP right now: ' + smsResult.message +
                '. Would you like to edit the mobile number or try resending the OTP?';
        }

        return output;
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
        
        String otpCode = generateOtpCode();
        System.debug('3. Generated Demo OTP: ' + otpCode);
        
        String message = 'Your secure banking OTP is: ' + otpCode + '. Do not share this with anyone.';
        
        System.debug('4. Phone is not blank. Initiating Twilio Service...');
        TwilioService.SmsResult smsResult = TwilioService.sendSMS(acc.Phone, message);

        result.success = smsResult.success;
        result.message = smsResult.message;

        if (smsResult.success == true) {
            result.otpCode = otpCode;
            update new Account(Id = acc.Id, Current_Session_OTP__c = otpCode);
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
        acc.Current_Session_OTP__c = null;
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

    private static String generateOtpCode() {
        Integer randomNum = Math.round(Math.random() * 8999) + 1000;
        return String.valueOf(randomNum);
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
