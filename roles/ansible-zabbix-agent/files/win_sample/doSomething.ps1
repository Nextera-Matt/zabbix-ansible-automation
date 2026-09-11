# This is a sample PowerShell script for Zabbix Windows custom checks

$uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$now = Get-Date
$uptimeInSeconds = ($now - $uptime).TotalSeconds
Write-Output [math]::Round($uptimeInSeconds)

