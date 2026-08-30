package com.abhishek.expense_tracker

/**
 * Lightweight Kotlin mirror of the Dart SmsParser's *gate* — just enough to
 * decide whether an incoming SMS looks like a money transaction, so the
 * receiver can post the right notification while the app is dead.
 * Full parsing happens in Dart when the queue is drained.
 */
object TxnGate {
    private val amountRe =
        Regex("""(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)

    // Some banks state the amount with no currency symbol at all, e.g. SBI's
    // "A/C X5942 debited by 1.00" — fall back to the number by the verb.
    private val amountNearVerbRe = Regex(
        """\b(?:debited|credited|spent|paid|sent|withdrawn|deducted|received|debit|credit)\s*(?:by|for|with|of|:)?\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)\b""",
        RegexOption.IGNORE_CASE
    )
    private val debitRe =
        Regex("""\b(debited|spent|paid|withdrawn|purchase|sent|deducted)\b""", RegexOption.IGNORE_CASE)
    private val creditRe =
        Regex("""\b(credited|received|deposited|refund(ed)?|reversed|cashback)\b""", RegexOption.IGNORE_CASE)
    private val rejectRe = Regex(
        """\b(otp|one\s*time\s*password|will\s+be\s+debited|due\s+(on|by)|min(imum)?\s+due|e-?mandate|autopay\s+is\s+set|offer|win|apply\s+now|last\s+date|requested\s+money|has\s+requested|payment\s+request|collect\s+request)\b""",
        RegexOption.IGNORE_CASE
    )

    data class Gate(val amount: String, val isDebit: Boolean)

    fun check(body: String): Gate? {
        val text = body.replace('\n', ' ')
        if (rejectRe.containsMatchIn(text)) return null
        val amount = (amountRe.find(text) ?: amountNearVerbRe.find(text))
            ?.groupValues?.get(1) ?: return null
        val d = debitRe.find(text)?.range?.first
        val c = creditRe.find(text)?.range?.first
        if (d == null && c == null) return null
        val isDebit = when {
            d != null && c != null -> d < c
            else -> d != null
        }
        return Gate(amount, isDebit)
    }
}
