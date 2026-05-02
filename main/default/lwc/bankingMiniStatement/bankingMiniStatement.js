import { LightningElement, api, track } from 'lwc';
import generateAndSendOtpWithStatus from '@salesforce/apex/IdentifyCustomerAction.generateAndSendOtpWithStatus';
import setSessionVerified from '@salesforce/apex/IdentifyCustomerAction.setSessionVerified';

const otpRequestCache = new Map();
const OTP_REQUEST_CACHE_MS = 60000;

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
    @track otpStatus = 'idle';
    @track otpDeliveryMessage = '';

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

    get isOtpSending() {
        return this.otpStatus === 'sending';
    }

    get isOtpSent() {
        return this.otpStatus === 'sent';
    }

    get hasOtpDeliveryError() {
        return this.otpStatus === 'error';
    }

    get isVerifyDisabled() {
        return this.isOtpSending || !this.generatedOtp || this.hasOtpDeliveryError;
    }

    get otpStatusText() {
        if (this.isOtpSending) {
            return 'Sending secure OTP...';
        }

        if (this.isOtpSent) {
            return this.otpDeliveryMessage || 'OTP sent successfully.';
        }

        if (this.hasOtpDeliveryError) {
            return this.otpDeliveryMessage || 'Unable to send OTP. Please try again.';
        }

        return '';
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

    sendNewOtp(forceRefresh = false) {
        if (!this.accountId) {
            this.otpStatus = 'error';
            this.otpDeliveryMessage = 'Account information is missing. OTP was not sent.';
            return;
        }

        const cachedRequest = otpRequestCache.get(this.accountId);
        const now = Date.now();

        if (
            !forceRefresh &&
            cachedRequest &&
            now - cachedRequest.createdAt < OTP_REQUEST_CACHE_MS
        ) {
            console.log('LWC: Reusing in-flight OTP request for Account ID:', this.accountId);
            this.handleOtpRequest(cachedRequest.promise);
            return;
        }

        console.log('LWC: Initiating OTP request for Account ID:', this.accountId);
        this.otpStatus = 'sending';
        this.otpDeliveryMessage = '';
        this.generatedOtp = '';

        const otpRequest = generateAndSendOtpWithStatus({ accountId: this.accountId });
        otpRequestCache.set(this.accountId, {
            createdAt: now,
            promise: otpRequest
        });

        this.handleOtpRequest(otpRequest);
    }

    handleOtpRequest(otpRequest) {
        this.otpStatus = 'sending';

        otpRequest
            .then(result => {
                console.log('LWC: Apex returned OTP response:', result);

                if (result?.success === true) {
                    this.otpStatus = 'sent';
                    this.generatedOtp = result.otpCode;
                    this.otpDeliveryMessage = result.message || 'OTP sent successfully.';
                } else {
                    otpRequestCache.delete(this.accountId);
                    this.otpStatus = 'error';
                    this.generatedOtp = '';
                    this.otpDeliveryMessage =
                        result?.message || 'Unable to send OTP. Please try again.';
                }

                this.userEnteredOtp = '';
                this.showError = false;
            })
            .catch(error => {
                otpRequestCache.delete(this.accountId);
                this.otpStatus = 'error';
                this.generatedOtp = '';
                this.otpDeliveryMessage = this.getErrorMessage(error);
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
        if (!this.generatedOtp || this.hasOtpDeliveryError) {
            this.showError = true;
            return;
        }

        if (this.userEnteredOtp === this.generatedOtp) {
            this.showError = false;

            setSessionVerified({ accountId: this.accountId });

            this.sessionVerifiedLocal = true;
        } else {
            this.showError = true;
        }
    }

    resendOtp() {
        this.sendNewOtp(true);
    }

    getErrorMessage(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Unable to send OTP. Please try again.'
        );
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
