import SwiftUI

struct ChatView: View {
    let username: String
    @State private var messageText: String = ""
    @State private var messages: [String] = [
        "Hey there!", "How's it going?"
    ]

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages.indices, id: \.self) { i in
                        HStack {
                            if i % 2 == 0 {
                                // Incoming message
                                Text(messages[i])
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(12)
                                    .frame(maxWidth: 250, alignment: .leading)
                            } else {
                                // Outgoing message
                                Spacer()
                                Text(messages[i])
                                    .padding()
                                    .background(Color.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .frame(maxWidth: 250, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    if !messageText.isEmpty {
                        messages.append(messageText)
                        messageText = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
    }
}
