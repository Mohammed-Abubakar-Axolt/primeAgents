public class TwilioService {
    
    // For a hackathon, hardcoding here is fastest. 
    // For production, these MUST go in Custom Metadata or Named Credentials.
    private static final String ACCOUNT_SID = 'AC064767e922c02c9d8acc4787e02a9dbc'; 
    private static final String AUTH_TOKEN = '11c05d2ca4dbc1fab82ec937d90c5c59';
    private static final String TWILIO_NUMBER = '+15076088301'; // Your Twilio Trial Number
    
    // We use @future so this callout runs asynchronously and doesn't block the UI
    @Future(callout=true)
    public static void sendSMS(String toPhone, String messageBody) {
        
        // Ensure the phone number has a country code (e.g., +91 for India)
        if(!toPhone.startsWith('+')) {
            toPhone = '+91' + toPhone; // Defaulting to India for this example
        }
        
        String endpoint = 'https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_SID + '/Messages.json';
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        
        // Twilio expects Basic Authentication
        String authHeader = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(ACCOUNT_SID + ':' + AUTH_TOKEN));
        req.setHeader('Authorization', authHeader);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        // Construct the URL-encoded payload
        String payload = 'To=' + EncodingUtil.urlEncode(toPhone, 'UTF-8') + 
                         '&From=' + EncodingUtil.urlEncode(TWILIO_NUMBER, 'UTF-8') + 
                         '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8');
        
        req.setBody(payload);
        
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 201) {
                System.debug('Twilio Success: SMS Sent');
            } else {
                System.debug('Twilio Error ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch(Exception e) {
            System.debug('Apex Callout Exception: ' + e.getMessage());
        }
    }
}