import { LightningElement, api, track } from 'lwc';

export default class BankingMiniStatement extends LightningElement {
    @api customerName;
    @api churnRisk;
    @api preferredLanguage;
    @api checkingBalance;
    @api creditCardBalance;
    @api loanOutstanding;
    @api transactionsJson;

    @track parsedTransactions = [];

    // Make the risk badge visually distinct
    get riskBadgeClass() {
        if (this.churnRisk === 'High') return 'slds-theme_error';
        if (this.churnRisk === 'Medium') return 'slds-theme_warning';
        return 'slds-theme_success';
    }

    connectedCallback() {
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
                console.error("Error parsing transactions", error);
            }
        }
    }
}