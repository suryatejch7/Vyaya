package com.vyaya.capture

/**
 * Cheap native pre-filter so only transaction-looking messages are queued.
 * The real parsing/validation (scams, promos, failed payments…) happens in
 * Dart (lib/services/capture/transaction_parser.dart).
 */
object CaptureFilter {

    /** Payment apps whose notifications we read. Bank SMS come via SmsReceiver. */
    val PAYMENT_APPS = setOf(
        "com.phonepe.app",                         // PhonePe
        "com.google.android.apps.nbu.paisa.user",  // Google Pay
        "net.one97.paytm",                         // Paytm
        "in.org.npci.upiapp",                      // BHIM
        "com.dreamplug.androidapp",                // CRED
        "in.amazon.mShop.android.shopping",        // Amazon Pay
        "com.naviapp",                             // Navi
        "com.mobikwik_new",                        // MobiKwik
        "com.freecharge.android"                   // Freecharge
    )

    private val AMOUNT = Regex("""(?:rs[.:]?|inr|₹)\s*[0-9]""", RegexOption.IGNORE_CASE)
    private val AMOUNT_BARE = Regex("""\b(?:debited|credited)\s+(?:by|for|with)\s+[0-9]""", RegexOption.IGNORE_CASE)
    private val MOVEMENT = Regex(
        """\b(debited|debit|credited|credit|spent|paid|withdrawn|purchase|deducted|sent|transferred|received|refund|refunded|deposited|txn|transaction|reversed|dr|cr|recharge|recharged)\b""",
        RegexOption.IGNORE_CASE
    )
    private val OTP = Regex("""\b(otp|one[\s-]?time\s*password|verification\s*code)\b""", RegexOption.IGNORE_CASE)

    fun looksLikeTransaction(text: String): Boolean {
        if (text.isBlank() || OTP.containsMatchIn(text)) return false
        return (AMOUNT.containsMatchIn(text) || AMOUNT_BARE.containsMatchIn(text)) &&
            MOVEMENT.containsMatchIn(text)
    }
}
