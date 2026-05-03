public with sharing class DisputeActionUtil {
    public class CustomerContext {
        public Account account;
        public Boolean isFound = false;
        public Boolean isVerified = false;
        public String message;
    }

    public static CustomerContext getVerifiedCustomer(String accountId, String mobileNumber) {
        CustomerContext context = new CustomerContext();

        List<Account> accounts;
        if (String.isNotBlank(accountId)) {
            accounts = [
                SELECT Id, Name, Phone, Is_Session_Verified__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
        } else if (String.isNotBlank(mobileNumber)) {
            accounts = [
                SELECT Id, Name, Phone, Is_Session_Verified__c
                FROM Account
                WHERE Phone = :mobileNumber
                LIMIT 1
            ];
        } else {
            context.message = 'Please provide the registered mobile number first.';
            return context;
        }

        if (accounts.isEmpty()) {
            context.message = 'No account was found for this mobile number. Please check the number and re-enter it in the chat.';
            return context;
        }

        context.account = accounts[0];
        context.isFound = true;
        context.isVerified = context.account.Is_Session_Verified__c == true;
        if (!context.isVerified) {
            context.message = 'Please complete OTP verification before filing a card dispute.';
        }

        return context;
    }

    public static Decimal extractAmount(String textValue) {
        if (String.isBlank(textValue)) {
            return null;
        }

        Matcher matcher = Pattern.compile('[0-9][0-9,]*(\\.[0-9]{1,2})?').matcher(textValue);
        if (!matcher.find()) {
            return null;
        }

        String amountText = matcher.group(0).replace(',', '');
        try {
            return Decimal.valueOf(amountText);
        } catch (Exception e) {
            return null;
        }
    }

    public static List<String> tokenize(String textValue) {
        List<String> tokens = new List<String>();
        if (String.isBlank(textValue)) {
            return tokens;
        }

        for (String token : textValue.toLowerCase().split('[^a-z0-9]+')) {
            if (token.length() >= 3) {
                tokens.add(token);
            }
        }

        return tokens;
    }

    public static String formatCurrency(Decimal amountValue) {
        if (amountValue == null) {
            return 'unknown amount';
        }

        return '₹' + amountValue.setScale(2).format();
    }

    public static String formatDate(Date dateValue) {
        return dateValue == null ? 'unknown date' : dateValue.format();
    }

    public static void setIfFieldExists(SObject recordValue, String fieldName, Object value) {
        if (recordValue.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
            recordValue.put(fieldName, value);
        }
    }

    public static Boolean picklistContains(Schema.SObjectField fieldToken, String value) {
        if (String.isBlank(value)) {
            return false;
        }

        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.getValue() == value) {
                return true;
            }
        }

        return false;
    }
}
