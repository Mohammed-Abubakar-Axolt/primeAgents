import { LightningElement, api, track } from 'lwc';

export default class BankingMiniStatement extends LightningElement {
    // These @api properties EXACTLY match the InvocableVariable names from Apex
    @api accountName;
    @api currentBalance;
    @api transactionsJson;

    @track parsedTransactions = [];

    connectedCallback() {
        if (this.transactionsJson) {
            try {
                let rawTxns = JSON.parse(this.transactionsJson);
                
                // Format the data for the UI
                this.parsedTransactions = rawTxns.map(txn => {
                    let isCredit = txn.Type === 'Credit';
                    return {
                        ...txn,
                        amountClass: isCredit ? 'slds-text-color_success' : 'slds-text-color_error',
                        sign: isCredit ? '+' : '-',
                        // Fallback to today if date is missing
                        formattedDate: txn.TransactionDate ? new Date(txn.TransactionDate).toLocaleDateString() : new Date().toLocaleDateString() 
                    };
                });
            } catch (error) {
                console.error("Error parsing transactions JSON", error);
            }
        }
    }
}