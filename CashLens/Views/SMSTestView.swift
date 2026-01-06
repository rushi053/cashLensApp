import SwiftUI

struct SMSTestView: View {
    @State private var smsText: String = ""
    @State private var parseResult: String = ""
    
    // Sample SMS messages for testing - Real Indian bank SMS formats
    private let sampleSMS = [
        // PhonePe
        "Dear Customer, Rs.250.00 paid to STARBUCKS COFFEE via PhonePe. UPI Ref no 401234567890. If not done by you, call us on 022-68727272 -PhonePe",
        
        // Google Pay  
        "₹150 sent to Uber India using Google Pay. UPI transaction ID: 123456789012",
        
        // SBI UPI
        "Dear Customer, Rs.500.00 debited from SBI A/c **1234 to Amazon Pay India Pvt Ltd via UPI Ref no 405678901234 on 25-Dec-23. Not you? Call 1800111109",
        
        // HDFC Bank
        "HDFC Bank: INR 300.00 debited from HDFC Bank A/c **5678 to SWIGGY on 25-Dec-23 16:30. UPI Ref# 234567890123. SMS STOP to 9210892108 to opt out",
        
        // ICICI Bank
        "ICICI Bank: Rs.750 debited from ICICI Bank A/c **9012 to ZOMATO MEDIA PVT LTD on 25-Dec-23. UPI:345678901234. Bal:Rs.12,345.67",
        
        // Paytm
        "Rs.200 debited from your bank account to BOOKMYSHOW via Paytm UPI. Transaction ID: 456789012345. Time: 25-Dec 16:45:32",
        
        // Axis Bank
        "Axis Bank: Rs.1,200 debited from Axis Bank A/c **3456 on 25-Dec-23 to BIGBASKET via UPI. Ref# 567890123456",
        
        // Amazon Pay
        "₹99 sent to NETFLIX INDIA via Amazon Pay UPI ID: amazone567890123456@apl",
        
        // CRED
        "₹1,500 paid to RELIANCE RETAIL via CRED UPI. Reference ID: cred789012345678",
        
        // Generic format
        "UPI:Rs.350 debited from Bank A/c ending 7890 to DMart Ready via UPI on 25-Dec-23. Ref:890123456789"
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("SMS Parser Test")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Paste your UPI SMS message below to test parsing:")
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SMS Text:")
                            .font(.headline)
                        
                        TextEditor(text: $smsText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    HStack {
                        Button("Parse SMS") {
                            testParsing()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Clear") {
                            smsText = ""
                            parseResult = ""
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    if !parseResult.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Parse Result:")
                                .font(.headline)
                            
                            Text(parseResult)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sample SMS Messages:")
                            .font(.headline)
                        
                        ForEach(Array(sampleSMS.enumerated()), id: \.offset) { index, sample in
                            Button(action: {
                                smsText = sample
                                testParsing()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sample \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(sample)
                                        .font(.system(.body, design: .monospaced))
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("SMS Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func testParsing() {
        guard !smsText.isEmpty else {
            parseResult = "Please enter SMS text first"
            return
        }
        
        if let transaction = UPISMSParser.parseUPITransaction(from: smsText) {
            parseResult = """
✅ Successfully Parsed!

Amount: ₹\(transaction.amount)
Merchant: \(transaction.merchant)
Payment Method: \(transaction.paymentMethod)
Source: \(transaction.source.rawValue)
Category: \(transaction.suggestedCategory.displayName)
Date: \(DateFormatter.localizedString(from: transaction.date, dateStyle: .short, timeStyle: .short))

UPI Reference: \(transaction.upiReference ?? "N/A")
Bank: \(transaction.bankName ?? "N/A")
Account: \(transaction.accountLastFour != nil ? "****\(transaction.accountLastFour!)" : "N/A")

Notes: \(transaction.notes ?? "None")
"""
        } else {
            parseResult = """
❌ Parsing Failed

Could not extract transaction details from this SMS. This could mean:
1. The SMS format is not recognized
2. The message doesn't contain UPI transaction info
3. The regex patterns need to be updated for this format

Please check the console output for detailed parsing logs.
"""
        }
    }
}

struct SMSTestView_Previews: PreviewProvider {
    static var previews: some View {
        SMSTestView()
    }
} 