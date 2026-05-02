import { LightningElement, api, track } from 'lwc';
import generateAndSendOtp from '@salesforce/apex/IdentifyCustomerAction.generateAndSendOtp';
import setSessionVerified from '@salesforce/apex/IdentifyCustomerAction.setSessionVerified';

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

    @track hasInitiatedOtp = false;
    @track sessionVerifiedLocal = false;
    @track parsedTransactions = [];
    @track generatedOtp = '';
    @track userEnteredOtp = '';
    @track showError = false;
    @track showCopyToast = false;

    get riskBadgeClass() {
        if (this.churnRisk === 'High') return 'risk-badge risk-high';
        if (this.churnRisk === 'Medium') return 'risk-badge risk-medium';
        return 'risk-badge risk-low';
    }

    get hasTransactions() {
        return this.parsedTransactions.length > 0;
    }

    get transactionCount() {
        return this.parsedTransactions.length;
    }

    connectedCallback() {
        this.sessionVerifiedLocal = this.isVerified === true || this.isVerified === 'true';

        if (!this.sessionVerifiedLocal && this.accountId && !this.hasInitiatedOtp) {
            this.hasInitiatedOtp = true;
            this.sendNewOtp();
        }

        if (this.transactionsJson) {
            try {
                const rawTxns = JSON.parse(this.transactionsJson);
                this.parsedTransactions = rawTxns.map(txn => {
                    const isCredit = txn.Type === 'Credit';
                    return {
                        ...txn,
                        amountClass: isCredit
                            ? 'txn-amount amount-credit'
                            : 'txn-amount amount-debit',
                        iconName: isCredit ? 'utility:arrowup' : 'utility:arrowdown',
                        sign: isCredit ? '+' : '-',
                        formattedDate: txn.TransactionDate
                            ? new Date(txn.TransactionDate).toLocaleDateString('en-IN', {
                                  day: '2-digit',
                                  month: 'short',
                                  year: 'numeric'
                              })
                            : 'Recent'
                    };
                });
            } catch (error) {
                console.error("Error parsing transactions JSON", error);
            }
        }
    }

    sendNewOtp() {
        console.log('LWC: Initiating OTP request for Account ID:', this.accountId);

        generateAndSendOtp({ accountId: this.accountId })
            .then(result => {
                console.log('LWC: Apex returned OTP successfully:', result);
                this.generatedOtp = result;
                this.userEnteredOtp = '';
                this.showError = false;
            })
            .catch(error => {
                console.error(
                    'LWC: CRITICAL ERROR calling Apex generateAndSendOtp:',
                    JSON.stringify(error)
                );
            });
    }

    handleOtpChange(event) {
        this.userEnteredOtp = event.target.value;
    }

    verifyOtp() {
        if (this.userEnteredOtp === this.generatedOtp) {
            this.showError = false;

            setSessionVerified({ accountId: this.accountId });

            this.sessionVerifiedLocal = true;
        } else {
            this.showError = true;
        }
    }

    resendOtp() {
        this.sendNewOtp();
    }

    copyPrompt(event) {
        const textToCopy = event.currentTarget.dataset.prompt;

        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(textToCopy);
            this.showCopyToast = true;

            setTimeout(() => {
                this.showCopyToast = false;
            }, 2000);
        }
    }
}
