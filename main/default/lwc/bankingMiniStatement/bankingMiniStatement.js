import { LightningElement, api, track } from 'lwc';
import generateAndSendOtpWithStatus from '@salesforce/apex/IdentifyCustomerAction.generateAndSendOtpWithStatus';
import setSessionVerified from '@salesforce/apex/IdentifyCustomerAction.setSessionVerified';
import getVerifiedBankingDetails from '@salesforce/apex/GetBankingDetailsAction.getVerifiedBankingDetails';

const otpRequestCache = new Map();
const OTP_REQUEST_CACHE_MS = 60000;

export default class BankingMiniStatement extends LightningElement {
    // Inputs from Apex Invocable
    @api accountId;
    @api isFound;
    @api isVerified;
    @api customerName;
    @api maskedPhone;
    @api churnRisk;
    @api preferredLanguage;
    @api checkingBalance;
    @api creditCardBalance;
    @api loanOutstanding;
    @api transactionsJson;
    @api statusMessage;

    @track hasInitiatedOtp = false;
    @track sessionVerifiedLocal = false;
    @track parsedTransactions = [];
    @track generatedOtp = '';
    @track userEnteredOtp = '';
    @track showError = false;
    @track showCopyToast = false;
    @track otpStatus = 'idle';
    @track otpDeliveryMessage = '';
    @track verificationErrorMessage = '';
    @track detailsStatus = 'idle';

    get noAccountFound() {
        return this.isFound === false || this.isFound === 'false' || !this.accountId;
    }

    get showOtpPanel() {
        return !this.noAccountFound && !this.sessionVerifiedLocal;
    }

    get showDashboard() {
        return !this.noAccountFound && this.sessionVerifiedLocal;
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
        return (
            this.isOtpSending ||
            this.isLoadingDetails ||
            !this.generatedOtp ||
            this.hasOtpDeliveryError
        );
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

    get isLoadingDetails() {
        return this.detailsStatus === 'loading';
    }

    get hasVerificationError() {
        return Boolean(this.verificationErrorMessage);
    }

    connectedCallback() {
        this.sessionVerifiedLocal = this.isVerified === true || this.isVerified === 'true';

        if (this.sessionVerifiedLocal && this.transactionsJson) {
            this.hydrateVerifiedDetails({
                accountId: this.accountId,
                customerName: this.customerName,
                preferredLanguage: this.preferredLanguage,
                checkingBalance: this.checkingBalance,
                creditCardBalance: this.creditCardBalance,
                loanOutstanding: this.loanOutstanding,
                transactionsJson: this.transactionsJson
            });
        }

        if (this.showOtpPanel && !this.hasInitiatedOtp) {
            this.hasInitiatedOtp = true;
            this.sendNewOtp();
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
            this.verificationErrorMessage = '';
            this.detailsStatus = 'loading';

            setSessionVerified({ accountId: this.accountId })
                .then(() => getVerifiedBankingDetails({ accountId: this.accountId }))
                .then(details => {
                    this.hydrateVerifiedDetails(details);
                    this.sessionVerifiedLocal = true;
                    this.detailsStatus = 'loaded';
                })
                .catch(error => {
                    this.detailsStatus = 'error';
                    this.verificationErrorMessage = this.getErrorMessage(error);
                    console.error(
                        'LWC: CRITICAL ERROR verifying session or loading banking details:',
                        JSON.stringify(error)
                    );
                });
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

    hydrateVerifiedDetails(details) {
        this.customerName = details?.customerName;
        this.preferredLanguage = details?.preferredLanguage;
        this.checkingBalance = details?.checkingBalance || 0;
        this.creditCardBalance = details?.creditCardBalance || 0;
        this.loanOutstanding = details?.loanOutstanding || 0;
        this.transactionsJson = details?.transactionsJson;
        this.parsedTransactions = this.parseTransactions(this.transactionsJson);
    }

    parseTransactions(transactionsJson) {
        if (!transactionsJson) {
            return [];
        }

        try {
            const rawTxns = JSON.parse(transactionsJson);
            return rawTxns.map(txn => {
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
            console.error('Error parsing transactions JSON', error);
            return [];
        }
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
