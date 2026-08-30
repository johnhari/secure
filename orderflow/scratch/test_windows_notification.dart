import 'dart:io';

void main() async {
  print('Testing Windows notification via PowerShell...');
  final psScript = r'''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$nodes = $xml.GetElementsByTagName('text')
$nodes.Item(0).AppendChild($xml.CreateTextNode('ADMIN DATA INJECTED')) | Out-Null
$nodes.Item(1).AppendChild($xml.CreateTextNode('Admin injected manual data on NIFTY50 at 24500.0')) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Orderflow Analyzer').Show($toast)
''';

  final result = await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psScript]);
  print('Exit code: ${result.exitCode}');
  print('Stdout: ${result.stdout}');
  print('Stderr: ${result.stderr}');
}
