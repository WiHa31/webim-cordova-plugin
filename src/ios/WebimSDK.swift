@objc(WebimSDK) class WebimSDK : CDVPlugin {
    private var session: WebimSession?
    private var messageTracker: MessageTracker?
    var onMessageCallbackId: String?
    var onTypingCallbackId: String?
    var onFileCallbackId: String?
    var onBanCallbackId: String?
    var onDialogCallbackId: String?
    var onFileMessageErrorCallbackId: String?
    var onConfirmCallbackId: String?


    func `init`(_ command: CDVInvokedUrlCommand) {
        var pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
        let callbackId = command.callbackId
        let args = command.arguments[0] as! NSDictionary
        let accountName = args["accountName"] as? String
        let location = args["location"] as? String
        if let accountName = accountName {
            var sessionBuilder = Webim.newSessionBuilder()
                .set(accountName: accountName)
                .set(location: location ?? "mobile")
            if let visitorFields = args["visitorFields"] as? NSDictionary {
                let jsonData = try? JSONSerialization.data(withJSONObject: visitorFields, options: [])
                let jsonString = String(data: jsonData!, encoding: .utf8)
                if let jsonString = jsonString {
                    sessionBuilder = sessionBuilder.set(visitorFieldsJSONString: jsonString)
                }
            }
            do {
                session = try sessionBuilder.build()
                session?.getStream().set(operatorTypingListener:self)
                session?.getStream().set(currentOperatorChangeListener: self)
                try messageTracker = session?.getStream().newMessageTracker(messageListener: self)
                try session?.resume()
                pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "{\"result\":\"Success\"}")
            } catch { }
        }
        self.commandDelegate!.send(
            pluginResult,
            callbackId: callbackId
        )
    }

    func onMessage(_ command: CDVInvokedUrlCommand) {
        onMessageCallbackId = command.callbackId
    }

    func onTyping(_ command: CDVInvokedUrlCommand) {
        onTypingCallbackId = command.callbackId
    }

    func onConfirm(_ command: CDVInvokedUrlCommand) {
        onConfirmCallbackId = command.callbackId
    }

    func onFile(_ command: CDVInvokedUrlCommand) {
        onFileCallbackId = command.callbackId
    }

    func onBan(_ command: CDVInvokedUrlCommand) {
        onBanCallbackId = command.callbackId
    }

    func onDialog(_ command: CDVInvokedUrlCommand) {
        onDialogCallbackId = command.callbackId
    }

    func close(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId
        if session != nil {
            do {
                try session?.destroy()
            } catch { }
            session = nil
            onMessageCallbackId = nil
            onTypingCallbackId = nil
            onFileCallbackId = nil
            onBanCallbackId = nil
            onDialogCallbackId = nil
            onFileMessageErrorCallbackId = nil
            sendCallbackResult(callbackId: callbackId!)
        } else {
            sendCallbackError(callbackId: callbackId!)
        }
    }

    func getMessagesHistory(_ command: CDVInvokedUrlCommand) {
        // TO DO
        let callbackId = command.callbackId
        let limit = command.arguments[0] as? Int
        let offset = command.arguments[1] as? Int
        if offset == 0 {
            do {
                try messageTracker?.getLastMessages(byLimit: limit ?? 25) { [weak self] messages in
                    var messagesSDK = [String]()
                    for message in messages {
                        messagesSDK.append((self?.messageToJSON(message: message))!)
                    }
                    self?.sendCallbackResult(callbackId: callbackId!, resultArray: messagesSDK)
                }
            } catch { }
        } else {
            do {
                try messageTracker?.getNextMessages(byLimit: limit ?? 25) { [weak self] messages in
                    var messagesSDK = [String]()
                    for message in messages {
                        messagesSDK.append((self?.messageToJSON(message: message))!)
                    }
                    self?.sendCallbackResult(callbackId: callbackId!, resultArray: messagesSDK)
                }
            } catch { }
        }
    }

    func typingMessage(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId
        let userMessage = command.arguments[0] as? String

        do {
            try session?.getStream().setVisitorTyping(draftMessage: userMessage?.count == 0 ? nil : userMessage)
        } catch { }
        sendCallbackResult(callbackId: callbackId!)
    }

    func requestDialog(_ command: CDVInvokedUrlCommand) {
        do {
            try session?.getStream().startChat()
            sendCallbackResult(callbackId: command.callbackId!)
        } catch { }
    }

    func sendMessage(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId
        let userMessage = command.arguments[0]
        var messageID: String?
        do {
            try messageID = session?.getStream().send(message: userMessage as! String)
        } catch { }
        let message = messageToJSON(id: messageID ?? "error", text: userMessage as! String, url: nil, timestamp: String(Int64(NSDate().timeIntervalSince1970 * 1000)), sender: nil)
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message)
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    func sendFile(_ command: CDVInvokedUrlCommand) {
        onFileMessageErrorCallbackId = command.callbackId
        let url = NSURL(string: (command.arguments[0] as? String)!)
        let fileName = url?.lastPathComponent
        let mimeType = MimeType(url: url! as URL)
        var file = Data()
        do {
            file = try Data(contentsOf: url! as URL)
        } catch { }
        do {
            try _ = session?.getStream().send(file: file,
                                              filename: fileName!,
                                              mimeType: mimeType.value,
                                              completionHandler: self)
        } catch { }
    }

    private func sendCallbackResult(callbackId: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    private func sendCallbackResult(callbackId: String, resultDictionary: Dictionary<AnyHashable, Any>) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: resultDictionary)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    private func sendCallbackResult(callbackId: String, resultArray: [Any]) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: resultArray)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    private func sendCallbackError(callbackId: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    private func sendCallbackError(callbackId: String, error: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error)
        self.commandDelegate!.send(pluginResult, callbackId: callbackId)
    }

    func messageToJSON(message: Message) -> String {
        var dict = [String: Any]()
        dict["id"] = message.getID()
        dict["text"] = message.getText()
        if message.getAttachment() != nil {
            do {
                dict["url"] = try String(contentsOf: (message.getAttachment()?.getURL())!)
            } catch { }
        }
        if message.getType() != .FILE_FROM_OPERATOR && message.getType() != .OPERATOR {
            dict["sender"] = message.getSenderName()
        } else {
            var `operator` = [String: String]()
            `operator`["firstname"] = message.getSenderName()
            `operator`["avatar"] = message.getSenderAvatarFullURL()?.absoluteString
            dict["operator"] = `operator`
        }
        dict["timestamp"] = String(message.getTime().timeIntervalSince1970 * 1000)
        if let JSONData = try? JSONSerialization.data(withJSONObject: dict,
                                                      options: .prettyPrinted),
            let JSONText = String(data: JSONData, encoding: String.Encoding.utf8) {
            return JSONText
        }
        return "";
    }

    func messageToJSON(id: String,
                       text: String,
                       url: String?,
                       timestamp: String,
                       sender: String?) -> String {
        var dict = [String: String]()
        dict["id"] = id
        dict["text"] = text
        dict["url"] = url
        dict["sender"] = sender
        dict["timestamp"] = timestamp
        if let JSONData = try? JSONSerialization.data(withJSONObject: dict,
                                                      options: .prettyPrinted),
            let JSONText = String(data: JSONData, encoding: String.Encoding.utf8) {
            return JSONText
        }
        return "";
    }

    func dialogStateToJSON(op: Operator?) -> String {
        var dict = [String: Any]()
        var employee = [String: String]()
        employee["id"] = op?.getID()
        employee["firstname"] = op?.getName()
        employee["avatar"] = op?.getAvatarURL()?.absoluteString
        dict["employee"] = employee

        if let JSONData = try? JSONSerialization.data(withJSONObject: dict,
                                                      options: .prettyPrinted),
            let JSONText = String(data: JSONData, encoding: String.Encoding.utf8) {
            return JSONText
        }
        return "";
    }
}

extension WebimSDK : OperatorTypingListener {
    func onOperatorTypingStateChanged(isTyping: Bool) {
        if onTypingCallbackId != nil {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "")
            pluginResult?.setKeepCallbackAs(true)
            self.commandDelegate!.send(pluginResult, callbackId: onTypingCallbackId)
        }
    }
}

extension WebimSDK: MessageListener {
    func added(message newMessage: Message, after previousMessage: Message?) {
        if newMessage.getType() != MessageType.FILE_FROM_OPERATOR
            && newMessage.getType() != MessageType.FILE_FROM_VISITOR {
            if onMessageCallbackId != nil && newMessage.getType() != .VISITOR {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: messageToJSON(message: newMessage))
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate!.send(pluginResult, callbackId: onMessageCallbackId)
            }
        } else {
            if onFileCallbackId != nil {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: messageToJSON(message: newMessage))
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate!.send(pluginResult, callbackId: onFileCallbackId)
            }
        }
    }

    func removed(message: Message) {

    }

    func removedAllMessages() {

    }

    func changed(message oldVersion: Message, to newVersion: Message) {
        if newVersion.getType() != MessageType.FILE_FROM_OPERATOR
            && newVersion.getType() != MessageType.FILE_FROM_VISITOR {
            if onConfirmCallbackId != nil {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: messageToJSON(message: newVersion))
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate!.send(pluginResult, callbackId: onConfirmCallbackId)
            }
        } else {
            if onFileCallbackId != nil {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: messageToJSON(message: newVersion))
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate!.send(pluginResult, callbackId: onFileCallbackId)
            }
        }
    }
}

extension WebimSDK : FatalErrorHandler {
    func on(error: WebimError) {
        let errorType = error.getErrorType()
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: true)
        pluginResult?.setKeepCallbackAs(true)
        switch errorType {
        case .ACCOUNT_BLOCKED:
            self.commandDelegate!.send(pluginResult, callbackId: onBanCallbackId)
            break
        case .PROVIDED_VISITOR_FIELDS_EXPIRED:
            break
        case .UNKNOWN:
            break
        case .VISITOR_BANNED:
            self.commandDelegate!.send(pluginResult, callbackId: onBanCallbackId)
            break
        case .WRONG_PROVIDED_VISITOR_HASH:
            break
        }
    }
}

extension WebimSDK : SendFileCompletionHandler {
    func onSuccess(messageID: String) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate!.send(pluginResult, callbackId: onFileMessageErrorCallbackId)
    }

    func onFailure(messageID: String, error: SendFileError) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR)
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate!.send(pluginResult, callbackId: onFileMessageErrorCallbackId)
    }

}

extension WebimSDK : CurrentOperatorChangeListener {
    func changed(operator previousOperator: Operator?, to newOperator: Operator?) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: dialogStateToJSON(op: newOperator))
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate!.send(pluginResult, callbackId: onDialogCallbackId)
    }


}
