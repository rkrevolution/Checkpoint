// Posts a distributed notification: used by e2e.sh to send Debug-only commands to the app.
// (osascript/JXA posts silently go nowhere, so this tiny helper is compiled instead.)
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: e2e-send <notification name>\n".utf8))
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(CommandLine.arguments[1]),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
