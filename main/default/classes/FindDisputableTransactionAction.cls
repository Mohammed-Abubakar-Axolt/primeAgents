public with sharing class FindDisputableTransactionAction {
    public class ActionInput {
        @InvocableVariable public String accountId;
        @InvocableVariable public String mobileNumber;
        @InvocableVariable public Decimal amount;
        @InvocableVariable public String merchantOrLocationHint;
        @InvocableVariable public String customerMessage;
    }

    public class ActionOutput {
        @InvocableVariable public Boolean isFound;
        @InvocableVariable public Boolean isVerified;
        @InvocableVariable public Boolean matchFound;
        @InvocableVariable public Boolean needsSelection;
        @InvocableVariable public String accountId;
        @InvocableVariable public String selectedTransactionId;
        @InvocableVariable public String financialAccountId;
        @InvocableVariable public Decimal matchConfidence;
        @InvocableVariable public String candidateTransactionsJson;
        @InvocableVariable public String messageText;
    }

    private class Candidate {
        public Id transactionId;
        public Id financialAccountId;
        public Decimal amount;
        public Datetime transactionDate;
        public String description;
        public String debitCreditIndicator;
        public String financialAccountName;
        public String financialAccountType;
        public Decimal score;
    }

    @InvocableMethod(label='Find Disputable Transaction' description='Finds the likely unauthorized transaction for a WhatsApp card dispute.')
    public static List<ActionOutput> findTransactions(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();
            DisputeActionUtil.CustomerContext context = DisputeActionUtil.getVerifiedCustomer(input.accountId, input.mobileNumber);
            output.isFound = context.isFound;
            output.isVerified = context.isVerified;

            if (!context.isFound || !context.isVerified) {
                output.messageText = context.message;
                outputs.add(output);
                continue;
            }

            output.accountId = context.account.Id;
            Decimal targetAmount = input.amount != null
                ? input.amount
                : DisputeActionUtil.extractAmount(input.customerMessage);
            String hintText = String.isNotBlank(input.merchantOrLocationHint)
                ? input.merchantOrLocationHint
                : input.customerMessage;
            List<String> tokens = DisputeActionUtil.tokenize(hintText);

            List<FinancialAccountTransaction> transactions = [
                SELECT Id, Amount, TransactionDate, Description, DebitCreditIndicator,
                       FinancialAccountId, FinancialAccount.Name, FinancialAccount.Type
                FROM FinancialAccountTransaction
                WHERE FinancialAccount.Primary_Owner__c = :context.account.Id
                ORDER BY TransactionDate DESC
                LIMIT 25
            ];

            List<Candidate> candidates = scoreCandidates(transactions, targetAmount, tokens);
            output.candidateTransactionsJson = JSON.serialize(candidates);

            if (candidates.isEmpty()) {
                output.matchFound = false;
                output.needsSelection = false;
                output.messageText = 'I could not find a matching transaction. Please share the amount, merchant/location, and approximate date.';
            } else {
                Candidate best = candidates[0];
                output.matchConfidence = best.score;
                output.selectedTransactionId = (String) best.transactionId;
                output.financialAccountId = (String) best.financialAccountId;
                output.matchFound = best.score >= 75;
                output.needsSelection = !output.matchFound;
                output.messageText = buildMessage(best, output.matchFound);
            }

            outputs.add(output);
        }

        return outputs;
    }

    private static List<Candidate> scoreCandidates(
        List<FinancialAccountTransaction> transactions,
        Decimal targetAmount,
        List<String> tokens
    ) {
        List<Candidate> candidates = new List<Candidate>();

        for (FinancialAccountTransaction txn : transactions) {
            Decimal score = 0;
            if (targetAmount != null && txn.Amount != null) {
                Decimal amountDifference = (txn.Amount - targetAmount).abs();
                if (amountDifference == 0) {
                    score += 60;
                } else if (amountDifference <= 100) {
                    score += 35;
                }
            }

            String description = String.valueOf(txn.Description).toLowerCase();
            for (String token : tokens) {
                if (description.contains(token)) {
                    score += 15;
                }
            }

            if (txn.DebitCreditIndicator == 'Debit') {
                score += 10;
            }
            if (txn.FinancialAccount != null && txn.FinancialAccount.Type == 'Credit Card') {
                score += 10;
            }
            if (txn.TransactionDate != null && txn.TransactionDate.date().daysBetween(Date.today()) <= 10) {
                score += 5;
            }

            if (score > 0) {
                Candidate candidate = new Candidate();
                candidate.transactionId = txn.Id;
                candidate.financialAccountId = txn.FinancialAccountId;
                candidate.amount = txn.Amount;
                candidate.transactionDate = txn.TransactionDate;
                candidate.description = txn.Description;
                candidate.debitCreditIndicator = txn.DebitCreditIndicator;
                candidate.financialAccountName = txn.FinancialAccount == null ? null : txn.FinancialAccount.Name;
                candidate.financialAccountType = txn.FinancialAccount == null ? null : txn.FinancialAccount.Type;
                candidate.score = Math.min(score, 100);
                candidates.add(candidate);
            }
        }

        candidates.sort(new CandidateSorter());
        return candidates;
    }

    private class CandidateSorter implements Comparator<Candidate> {
        public Integer compare(Candidate leftValue, Candidate rightValue) {
            if (leftValue.score == rightValue.score) {
                return 0;
            }
            return leftValue.score > rightValue.score ? -1 : 1;
        }
    }

    private static String buildMessage(Candidate best, Boolean matchFound) {
        String prefix = matchFound ? 'I found a matching transaction: ' : 'I found a possible transaction: ';
        return prefix +
            best.description + ' for ' + DisputeActionUtil.formatCurrency(best.amount) +
            ' on ' + DisputeActionUtil.formatDate(best.transactionDate == null ? null : best.transactionDate.date()) +
            ' from ' + best.financialAccountName + '.';
    }
}
