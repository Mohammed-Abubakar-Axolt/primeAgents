import { LightningElement, api, track } from 'lwc';
import generateAndSendOtp from '@salesforce/apex/OtpServiceController.generateAndSendOtp';
import setSessionVerified from '@salesforce/apex/OtpServiceController.setSessionVerified';

export default class BankingMiniStatement extends LightningElement {
    // Inputs from Apex Invocable
    @api accountId;
    @api isVerified; 
    @api customerName;
    @api maskedPhone;
    @api churnRisk;
    @api preferredLanguage;
    @api checkingBalance;
    @api creditCardBalance;
    @api loanOutstanding;
    @api transactionsJson;

    // Local State
    @track sessionVerifiedLocal = false;
    @track parsedTransactions = [];
    @track generatedOtp = '';
    @track userEnteredOtp = '';
    @track showError = false;

    get riskBadgeClass() {
        if (this.churnRisk === 'High') return 'slds-theme_error';
        if (this.churnRisk === 'Medium') return 'slds-theme_warning';
        return 'slds-theme_success';
    }

    connectedCallback() {
        this.sessionVerifiedLocal = this.isVerified;
        
        // If not verified, trigger the Twilio Apex class immediately
        if (!this.sessionVerifiedLocal && this.accountId) {
            this.sendNewOtp();
        }

        // Parse transactions for the dashboard
        if (this.transactionsJson) {
            try {
                let rawTxns = JSON.parse(this.transactionsJson);
                this.parsedTransactions = rawTxns.map(txn => {
                    let isCredit = txn.Type === 'Credit';
                    return {
                        ...txn,
                        amountClass: isCredit ? 'slds-text-color_success slds-text-title_bold' : 'slds-text-color_error',
                        sign: isCredit ? '+' : '-',
                        formattedDate: txn.TransactionDate ? new Date(txn.TransactionDate).toLocaleDateString() : 'Recent' 
                    };
                });
            } catch (error) {
                console.error("Error parsing transactions JSON", error);
            }
        }
    }

    sendNewOtp() {
        generateAndSendOtp({ accountId: this.accountId })
            .then(result => {
                this.generatedOtp = result;
                this.userEnteredOtp = '';
                this.showError = false;
            })
            .catch(error => { console.error('Error generating OTP', error); });
    }

    handleOtpChange(event) {
        this.userEnteredOtp = event.target.value;
    }

    verifyOtp() {
        if (this.userEnteredOtp === this.generatedOtp) {
            this.showError = false;
            
            // 1. Tell Salesforce the session is now secure
            setSessionVerified({ accountId: this.accountId });
            
            // 2. Instantly switch the UI to show the Banking Dashboard!
            this.sessionVerifiedLocal = true; 
        } else {
            this.showError = true;
        }
    }

    resendOtp() {
        this.sendNewOtp();
    }
}