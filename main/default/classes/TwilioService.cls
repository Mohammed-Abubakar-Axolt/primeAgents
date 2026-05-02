public class TwilioService {
    
    // For a hackathon, hardcoding here is fastest. 
    // For production, these MUST go in Custom Metadata or Named Credentials.
    // private static final String ACCOUNT_SID = 'AC064767e922c02c9d8acc4787e02a9dbc'; 
    // private static final String AUTH_TOKEN = '11c05d2ca4dbc1fab82ec937d90c5c59';

    private static final String ACCOUNT_SID = System.Label.Twilio_SID; 
    private static final String AUTH_TOKEN = System.Label.Twilio_Token;
    private static final String TWILIO_NUMBER = '+15076088301'; // Your Twilio Trial Number
    
    // We use @future so this callout runs asynchronously and doesn't block the UI
    @Future(callout=true)
    public static void sendSMS(String toPhone, String messageBody) {
        System.debug('--- TWILIO SERVICE TRIGGERED ---');
        System.debug('Original toPhone: ' + toPhone);
        
        // Ensure country code
        if(!toPhone.startsWith('+')) {
            toPhone = '+91' + toPhone; 
        }
        System.debug('Formatted toPhone (with country code): ' + toPhone);
        
        String endpoint = 'https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_SID + '/Messages.json';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        
        String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(ACCOUNT_SID + ':' + AUTH_TOKEN));
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        String payload = 'To=' + EncodingUtil.urlEncode(toPhone, 'UTF-8') + 
                         '&From=' + EncodingUtil.urlEncode(TWILIO_NUMBER, 'UTF-8') + 
                         '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8');
        
        System.debug('Twilio Payload: ' + payload);
        
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            System.debug('Twilio HTTP Status Code: ' + res.getStatusCode());
            System.debug('Twilio Raw Response Body: ' + res.getBody()); // THIS WILL TELL US THE ERROR
            
            if (res.getStatusCode() == 201) {
                System.debug('Twilio Success: SMS Sent correctly!');
            } else {
                System.debug('Twilio Failure: Something went wrong with the API call.');
            }
        } catch(Exception e) {
            System.debug('CRITICAL Apex Callout Exception: ' + e.getMessage());
        }
    }
}