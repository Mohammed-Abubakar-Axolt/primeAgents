import { LightningElement, api, track } from 'lwc';
import generateAndSendOtp from '@salesforce/apex/OtpServiceController.generateAndSendOtp';
import setSessionVerified from '@salesforce/apex/OtpServiceController.setSessionVerified';

export default class InteractiveVerificationWidget extends LightningElement {
    // Inputs from Agentforce
    @api accountId;
    @api customerName;
    @api maskedPhone;
    @api isFound;

    // UI State
    @track isVerified = false;
    @track showOtpScreen = false;
    @track generatedOtp = '';
    @track userEnteredOtp = '';
    @track showError = false;
    @track showCopyToast = false;

    connectedCallback() {
        if (this.isFound) {
            this.showOtpScreen = true;
            this.sendNewOtp();
        }
    }

    sendNewOtp() {
        generateAndSendOtp({ accountId: this.accountId })
            .then(result => {
                this.generatedOtp = result;
                this.userEnteredOtp = '';
                this.showError = false;
            })
            .catch(error => {
                console.error('Error generating OTP', error);
            });
    }

    handleOtpChange(event) {
        this.userEnteredOtp = event.target.value;
    }

    verifyOtp() {
        if (this.userEnteredOtp === this.generatedOtp) {
            this.showError = false;
            this.showOtpScreen = false;
            this.isVerified = true;
            
            // Tell Salesforce Backend they are verified
            setSessionVerified({ accountId: this.accountId });
        } else {
            this.showError = true;
        }
    }

    resendOtp() {
        this.sendNewOtp();
    }

    editNumber() {
        // Instruct user to interact with the bot again
        this.showOtpScreen = false;
        this.isFound = false; // Triggers the error/retry screen
    }

    copyPrompt(event) {
        const textToCopy = event.currentTarget.dataset.prompt;
        
        // Standard browser clipboard copy
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(textToCopy);
            this.showCopyToast = true;
            setTimeout(() => { this.showCopyToast = false; }, 2000);
        }
    }
}