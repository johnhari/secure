import subprocess
import base64

script = """
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$nodes = $xml.GetElementsByTagName('text')
$nodes.Item(0).AppendChild($xml.CreateTextNode('Orderflow Alert: NIFTY50')) | Out-Null
$nodes.Item(1).AppendChild($xml.CreateTextNode('Buy Vol: 25.4K | Sell Vol: 2.1K @ ₹24,350')) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::new($xml)
try {
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe')
    $notifier.Show($toast)
    Write-Host "TOAST DISPATCHED SUCCESSFULLY!"
} catch {
    Write-Host "ERROR: $_"
}
"""

encoded = base64.b64encode(script.encode('utf-16le')).decode('ascii')
res = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded], capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
